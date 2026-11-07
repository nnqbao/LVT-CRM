import Foundation

struct WorkUploadedEvidence: Sendable {
    let driveFileId: String
    let driveChecksum: String
    let cleanupToken: String
    let fileName: String
    let fileType: String
    let fileSize: Int
}

struct WorkFormDepartment: Equatable, Sendable {
    let id: String
    let name: String
}

struct WorkFormUser: Equatable, Sendable {
    let id: String
    let name: String
    let departmentName: String
    let level: Int
    var positionName: String = ""
}

struct WorkDocumentType: Equatable, Sendable {
    let id: String
    let name: String
    let code: String
}

struct WorkFormOptions: Equatable, Sendable {
    let canCreate: Bool
    let isOps: Bool
    let departments: [WorkFormDepartment]
    let users: [WorkFormUser]
    let documentTypes: [WorkDocumentType]
    /// Creator-based rule from the server: admin/mod documents go to Ban giám hiệu first.
    var requiresApproval: Bool = false
    /// Whole-department assignments (admin/mod and Ban giám hiệu), decided by the server.
    var canAssignDepartments: Bool = false
    /// Eligible Ban giám hiệu approvers (only sent when approval is required).
    var approvers: [WorkFormUser] = []

    /// `work:formOptions`. Flags come from the server; nothing is derived from position levels here.
    static func decode(
        _ result: [String: Any],
        documentTypes: [WorkDocumentType],
        departments: [WorkFormDepartment]
    ) -> WorkFormOptions {
        func people(_ value: Any?) -> [WorkFormUser] {
            ((value as? [[String: Any]]) ?? []).compactMap { item in
                let id = (item["_id"] as? String) ?? ""
                guard !id.isEmpty else { return nil }
                let name = ((item["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return WorkFormUser(
                    id: id,
                    name: name.isEmpty ? ((item["email"] as? String) ?? "") : name,
                    departmentName: (item["departmentName"] as? String) ?? "",
                    level: (item["level"] as? NSNumber)?.intValue ?? 0,
                    positionName: (item["positionName"] as? String) ?? ""
                )
            }
        }
        let isOps = (result["isOps"] as? Bool) ?? false
        return WorkFormOptions(
            canCreate: (result["canCreate"] as? Bool) ?? false,
            isOps: isOps,
            departments: departments,
            users: people(result["users"]),
            documentTypes: documentTypes,
            requiresApproval: (result["requiresApproval"] as? Bool) ?? false,
            // Older servers omit the flag: only admin/mod could assign departments then.
            canAssignDepartments: (result["canAssignDepartments"] as? Bool) ?? isOps,
            approvers: people(result["approvers"])
        )
    }
}

struct WorkCreateAssignment: Equatable {
    var type: String
    var departmentId: String
    var userIds: [String]
    var content: String
    var deadline: String

    var isIndividual: Bool { type == "individual" }

    static func department() -> WorkCreateAssignment {
        WorkCreateAssignment(type: "department", departmentId: "", userIds: [], content: "", deadline: "")
    }

    static func individual() -> WorkCreateAssignment {
        WorkCreateAssignment(type: "individual", departmentId: "", userIds: [], content: "", deadline: "")
    }
}

enum WorkCreatePolicy {
    static func validate(
        title: String,
        assignments: [WorkCreateAssignment],
        hasFile: Bool = false,
        documentTypeId: String = "",
        approversRequired: Bool = false,
        approverCount: Int = 0
    ) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 200 {
            return "Vui lòng nhập tên công việc (tối đa 200 ký tự)."
        }
        if assignments.isEmpty {
            return "Vui lòng thêm ít nhất một phân công."
        }
        if hasFile && documentTypeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Vui lòng chọn loại văn bản."
        }
        for (index, row) in assignments.enumerated() {
            let label = "Phân công \(index + 1)"
            if row.isIndividual {
                if row.userIds.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    return "\(label): chọn người nhận."
                }
            } else if row.departmentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(label): chọn phòng ban."
            }
            let content = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty || content.count > 2000 {
                return "\(label): nhập nội dung công việc (tối đa 2000 ký tự)."
            }
            if row.deadline.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
                return "\(label): chọn hạn chót."
            }
        }
        if approversRequired && approverCount == 0 {
            return "Vui lòng chọn ít nhất một người duyệt thuộc Ban giám hiệu."
        }
        return nil
    }

    /// `work:createDocument` / `work:updateDocument` arguments. `approverUserIds` is sent whenever the creator
    /// picked approvers; the server decides whether the document needs them.
    static func mutationArgs(
        title: String,
        assignments: [WorkCreateAssignment],
        evidence: WorkUploadedEvidence?,
        documentTypeId: String?,
        approverUserIds: [String]
    ) -> [String: Any] {
        var payload: [[String: Any]] = []
        for row in assignments {
            var item: [String: Any] = [
                "type": row.type,
                "content": row.content.trimmingCharacters(in: .whitespacesAndNewlines),
                "deadline": row.deadline.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            if row.isIndividual {
                item["userIds"] = row.userIds.filter { !$0.isEmpty }
            } else {
                item["departmentId"] = row.departmentId
            }
            payload.append(item)
        }
        var args: [String: Any] = [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "assignments": payload,
        ]
        if let documentTypeId, !documentTypeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args["documentTypeId"] = documentTypeId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var seen = Set<String>()
        let approvers = approverUserIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if !approvers.isEmpty {
            args["approverUserIds"] = approvers
        }
        if let evidence {
            args["driveFileId"] = evidence.driveFileId
            args["driveChecksum"] = evidence.driveChecksum
            args["cleanupToken"] = evidence.cleanupToken
            args["fileName"] = evidence.fileName
            args["fileType"] = evidence.fileType
            args["fileSize"] = evidence.fileSize
        }
        return args
    }

    /// Edit/delete failures keep the server's mapped message (approval lock, scope, assignee rules…).
    static func actionError(raw: String, deleting: Bool, fallback: String) -> String {
        let code = ConvexHttpClient.extractCode(raw)
        if let message = ConvexHttpClient.workMessage(code) { return message }
        if deleting { return "Không thể xóa công văn lúc này." }
        return fallback
    }

    static func formatDeadline(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

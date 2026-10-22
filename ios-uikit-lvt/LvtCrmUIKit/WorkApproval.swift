import Foundation

/// Ban giám hiệu approval of work documents (web `WorkApprovalParts.jsx` / `workDisplay.js`, backend
/// `convex/workDocumentPolicy.ts`). Pure Foundation: models, decoding, display and state rules. The server
/// decides who needs approval, who may approve and whether edit/delete is still allowed; these helpers only
/// render the flags it returns.

struct WorkMemberItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
}

struct WorkDocumentAssignment: Identifiable, Equatable, Sendable {
    let id: String
    let departmentName: String
    let content: String
    let deadline: String
    let status: String
    let members: [WorkMemberItem]
    var type: String = ""
    var departmentId: String = ""
    var userIds: [String] = []
}

/// One designated approver with their decision (`documentView.approvers`).
struct WorkApproverInfo: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let level: Int
    let approved: Bool
    let rejected: Bool
    /// Epoch milliseconds of the decision, nil while waiting.
    let decidedAt: Int64?
    let reason: String
}

struct WorkApprovalItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let fileName: String
    let fileURL: String
    let privateFile: Bool
    let content: String
    let deadline: String
    /// Document approval status: `pending` (chờ duyệt), `approved` (released), `rejected` (bị trả lại).
    let status: String
    let approvalCount: Int
    let approvalTotal: Int
    var myDecision: String
    let assignments: [WorkDocumentAssignment]
    var canEdit: Bool = false
    var canDelete: Bool = false
    var documentTypeId: String = ""
    /// Aggregate list status from `listAdmin` (`awaiting_approval`, `approval_returned`, `in_progress`, …).
    var workStatus: String = ""
    var requiresApproval: Bool = false
    /// First approval permanently locks edit/delete (server flag).
    var approvalLocked: Bool = false
    var returnReason: String = ""
    var approvers: [WorkApproverInfo] = []
    var creatorName: String = ""
    var creatorRole: String = ""
    var submittedAt: Int64? = nil
    /// Approver queue only: this user still has to decide.
    var awaitingMyDecision: Bool = false
    /// Approver queue only: return is still allowed (nobody approved yet).
    var canReject: Bool = false
    /// Newer servers: editing this (already approved) document sends it back to Ban giám hiệu. nil = not sent.
    var editRequiresReapproval: Bool? = nil
    /// Newer servers: an assignee submitted results, so the document is read-only. nil = not sent.
    var hasSubmissions: Bool? = nil
    var lastEditedByName: String = ""
    var lastEditedAt: Int64? = nil
    /// The server sent `canEdit` / `canDelete` (absent on malformed or older rows).
    var hasServerActionFlags: Bool = false

    func editAssignments() -> [WorkCreateAssignment] {
        assignments.flatMap { row in
            let individual = row.type == "individual" ||
                (row.type.isEmpty && row.departmentId.isEmpty &&
                    (!row.userIds.isEmpty || row.departmentName == "Cá nhân"))
            if !individual {
                return [WorkCreateAssignment(
                    type: "department",
                    departmentId: row.departmentId,
                    userIds: [],
                    content: row.content,
                    deadline: row.deadline
                )]
            }
            let ids = row.userIds.filter { !$0.isEmpty }
            let people = ids.isEmpty ? row.members.map(\.id).filter { !$0.isEmpty } : ids
            let resolved = people.isEmpty ? [""] : people
            return resolved.map { id in
                WorkCreateAssignment(
                    type: "individual",
                    departmentId: "",
                    userIds: id.isEmpty ? [] : [id],
                    content: row.content,
                    deadline: row.deadline
                )
            }
        }
    }
}

enum WorkApprovalDecoding {
    static func string(_ value: Any?) -> String {
        (value as? String) ?? ""
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, !(value is Bool) {
            return number.intValue
        }
        return value as? Int
    }

    static func millis(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, !(value is Bool) else { return nil }
        let millis = number.int64Value
        return millis > 0 ? millis : nil
    }

    static func bool(_ value: Any?) -> Bool {
        (value as? Bool) ?? false
    }

    static func approvers(_ value: Any?) -> [WorkApproverInfo] {
        ((value as? [[String: Any]]) ?? []).compactMap { row in
            let id = string(row["_id"])
            guard !id.isEmpty else { return nil }
            let name = string(row["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkApproverInfo(
                id: id,
                name: name.isEmpty ? string(row["email"]) : name,
                level: int(row["level"]) ?? 0,
                approved: bool(row["approved"]),
                rejected: bool(row["rejected"]),
                decidedAt: millis(row["decidedAt"]),
                reason: string(row["reason"])
            )
        }
    }

    static func assignments(_ items: [[String: Any]]?) -> [WorkDocumentAssignment] {
        (items ?? []).map { item in
            let members = (item["members"] as? [[String: Any]] ?? []).map { member in
                let name = string(member["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
                return WorkMemberItem(
                    id: string(member["_id"]),
                    name: name.isEmpty ? string(member["email"]) : name,
                    status: string(member["status"])
                )
            }
            let userIds = (item["userIds"] as? [String]) ?? []
            return WorkDocumentAssignment(
                id: string(item["_id"]),
                departmentName: string(item["departmentName"]),
                content: string(item["content"]),
                deadline: string(item["deadline"]),
                status: string(item["status"]),
                members: members,
                type: string(item["type"]),
                departmentId: string(item["departmentId"]),
                userIds: userIds.filter { !$0.isEmpty }
            )
        }
    }

    /// One `documentView` row (from `work:listAdmin` documents or `work:listMine` approvals).
    static func document(_ document: [String: Any], currentUserId: String, fileURL: String) -> WorkApprovalItem {
        let approvers = approvers(document["approvers"])
        let mine = approvers.first { $0.id == currentUserId && !currentUserId.isEmpty }
        let myDecision = mine.map { $0.approved ? "approved" : ($0.rejected ? "rejected" : "") } ?? ""
        return WorkApprovalItem(
            id: string(document["_id"]),
            title: string(document["title"]),
            fileName: string(document["fileName"]),
            fileURL: fileURL,
            privateFile: bool(document["privateFile"]),
            content: string(document["content"]),
            deadline: string(document["deadline"]),
            status: string(document["status"]),
            approvalCount: int(document["approvalCount"]) ?? 0,
            approvalTotal: int(document["approvalTotal"]) ?? approvers.count,
            myDecision: myDecision,
            assignments: assignments(document["assignments"] as? [[String: Any]]),
            canEdit: bool(document["canEdit"]),
            canDelete: bool(document["canDelete"]),
            documentTypeId: string(document["documentTypeId"]),
            workStatus: string(document["workStatus"]),
            requiresApproval: bool(document["requiresApproval"]),
            approvalLocked: bool(document["approvalLocked"]),
            returnReason: string(document["returnReason"]),
            approvers: approvers,
            creatorName: string(document["creatorName"]),
            creatorRole: string(document["creatorRole"]),
            submittedAt: millis(document["submittedAt"]),
            awaitingMyDecision: bool(document["awaitingMyDecision"]),
            canReject: bool(document["canReject"]),
            editRequiresReapproval: document["editRequiresReapproval"] as? Bool,
            hasSubmissions: document["hasSubmissions"] as? Bool,
            lastEditedByName: string(document["lastEditedByName"]).trimmingCharacters(in: .whitespacesAndNewlines),
            lastEditedAt: millis(document["lastEditedAt"]),
            hasServerActionFlags: document["canEdit"] is Bool && document["canDelete"] is Bool
        )
    }

    /// Approver queue: awaiting my decision first, then newest submission (server order, kept stable).
    static func orderedQueue(_ items: [WorkApprovalItem]) -> [WorkApprovalItem] {
        items.enumerated().sorted { lhs, rhs in
            if lhs.element.awaitingMyDecision != rhs.element.awaitingMyDecision {
                return lhs.element.awaitingMyDecision
            }
            let left = lhs.element.submittedAt ?? 0
            let right = rhs.element.submittedAt ?? 0
            if left != right { return left > right }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

enum WorkApprovalRules {
    static let returnReasonMaxLength = 500
    static let approvalNote = "Công việc do Văn thư/Quản trị tạo cần Ban giám hiệu duyệt trước khi giao."
    static let approverPickerTitle = "Người duyệt (Ban giám hiệu)"
    static let approvalLockedMessage = "Đã có người duyệt · Không thể sửa hoặc xóa"
    static let submissionLockedMessage = "Đã có người nộp · Không thể sửa hoặc xóa"
    static let approveConfirmMessage = "Sau khi bạn duyệt, công việc không thể sửa hoặc xóa nữa. Khi đủ người duyệt, công việc được giao ngay cho người nhận."
    static let returnHint = "Người tạo sẽ sửa và gửi duyệt lại."

    /// Web `isWorkDocumentUnreleased`: not handed to anyone yet.
    static func isUnreleased(_ document: WorkApprovalItem) -> Bool {
        document.requiresApproval && document.status != "approved"
    }

    /// Web `workAssignmentDisplayStatus`.
    static func assignmentDisplayStatus(_ document: WorkApprovalItem, _ assignment: WorkDocumentAssignment) -> String {
        if isUnreleased(document) { return "unreleased" }
        return assignment.status.isEmpty ? "unassigned" : assignment.status
    }

    /// List status: aggregate `workStatus` when the server sent one, else the document status.
    static func effectiveStatus(_ document: WorkApprovalItem) -> String {
        document.workStatus.isEmpty ? document.status : document.workStatus
    }

    /// Web `workStatusLabel` (shared by work items, assignments and documents).
    static func statusLabel(_ status: String) -> String {
        switch status {
        case "pending", "awaiting_approval": return "Chờ duyệt"
        case "approved": return "Đã duyệt"
        case "rejected", "approval_returned": return "Bị trả lại"
        case "unassigned": return "Chưa giao việc"
        case "unreleased": return "Chờ duyệt (chưa giao)"
        case "in_progress": return "Đang thực hiện"
        case "completed": return "Đã hoàn thành"
        case "completed_late": return "Hoàn thành trễ"
        case "pending_completion": return "Chờ duyệt hoàn thành"
        case "rejected_completion": return "Bị từ chối hoàn thành"
        case "not_completed", "pending_task": return "Chưa hoàn thành"
        case "overdue": return "Quá hạn"
        default: return "Chưa cập nhật"
        }
    }

    /// "Ban giám hiệu duyệt 1/2" while the document went through approval; nil otherwise.
    static func progressText(_ document: WorkApprovalItem) -> String? {
        let total = max(document.approvalTotal, document.approvers.count)
        guard total > 0 else { return nil }
        return "Ban giám hiệu duyệt \(document.approvalCount)/\(total)"
    }

    /// Creator card status: approval state first, then the work progress once released.
    static func creatorStatusText(_ document: WorkApprovalItem) -> String {
        let label = statusLabel(effectiveStatus(document))
        let total = max(document.approvalTotal, document.approvers.count)
        guard total > 0, document.status != "approved" else { return label }
        return "\(label) · \(document.approvalCount)/\(total)"
    }

    static func returnReasonText(_ document: WorkApprovalItem) -> String? {
        let reason = document.returnReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard document.status == "rejected", !reason.isEmpty else { return nil }
        return "Lý do trả lại: \(reason)"
    }

    /// Approver-queue status for the current approver.
    static func queueStatusText(_ document: WorkApprovalItem) -> String {
        if document.awaitingMyDecision { return "Chờ bạn duyệt" }
        if document.status == "rejected" { return "Đã trả lại" }
        if document.myDecision == "approved" {
            return document.status == "approved" ? "Đã duyệt" : "Bạn đã duyệt · chờ người khác"
        }
        return statusLabel(document.status)
    }

    /// Web `workApproverDecisionLabel`.
    static func approverDecisionLabel(_ approver: WorkApproverInfo) -> String {
        let when = approver.decidedAt.map(formatDateTime) ?? ""
        if approver.approved { return when.isEmpty ? "Đã duyệt" : "Đã duyệt \(when)" }
        if approver.rejected { return when.isEmpty ? "Trả lại" : "Trả lại \(when)" }
        return "Chờ duyệt"
    }

    static func approverLines(_ document: WorkApprovalItem) -> [String] {
        document.approvers.map { "\($0.name) · \(approverDecisionLabel($0))" }
    }

    /// Web `workCreatorLabel`: "Người tạo: Tên (Văn thư)".
    static func creatorLabel(_ document: WorkApprovalItem) -> String {
        let name = document.creatorName.isEmpty ? "—" : document.creatorName
        let role: String
        switch document.creatorRole {
        case "admin": role = "Quản trị viên"
        case "moderator": role = "Văn thư"
        default: role = ""
        }
        return role.isEmpty ? "Người tạo: \(name)" : "Người tạo: \(name) (\(role))"
    }

    /// dd/MM/yyyy HH:mm in Vietnam time.
    static func formatDateTime(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        )
        return String(
            format: "%02d/%02d/%04d %02d:%02d",
            parts.day ?? 0, parts.month ?? 0, parts.year ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }

    static let reapprovalWarning = "Công việc đã được duyệt. Sau khi lưu, công việc sẽ phải gửi Ban giám hiệu duyệt lại và tạm ẩn với người được giao."
    static let submissionsReadOnlyMessage = "Đã có người nộp kết quả — công việc chỉ xem."

    /// Newer servers send the per-document edit policy (`editRequiresReapproval` / `hasSubmissions`):
    /// then `canEdit` / `canDelete` alone decide (admin may edit an approved document; everyone is read-only
    /// after a submission).
    static func serverDrivesActions(_ document: WorkApprovalItem) -> Bool {
        document.hasServerActionFlags && (document.editRequiresReapproval != nil || document.hasSubmissions != nil)
    }

    /// Edit/delete buttons. Server-driven when the server sends its policy; otherwise (older server) never
    /// after the first approval, else the server flag, and admin/mod keep editing after a submission.
    static func showsEdit(_ document: WorkApprovalItem, isOps: Bool) -> Bool {
        if serverDrivesActions(document) { return document.canEdit }
        return !document.approvalLocked && (document.canEdit || isOps)
    }

    static func showsDelete(_ document: WorkApprovalItem, isOps: Bool) -> Bool {
        if serverDrivesActions(document) { return document.canDelete }
        return !document.approvalLocked && (document.canDelete || isOps)
    }

    static func lockedMessage(_ document: WorkApprovalItem, isOps: Bool) -> String? {
        if showsEdit(document, isOps: isOps) || showsDelete(document, isOps: isOps) { return nil }
        if serverDrivesActions(document) {
            if document.hasSubmissions == true { return submissionsReadOnlyMessage }
            return document.approvalLocked ? approvalLockedMessage : nil
        }
        return document.approvalLocked ? approvalLockedMessage : submissionLockedMessage
    }

    /// Edit form: saving an approved document sends it back to Ban giám hiệu (server flag).
    static func editNeedsReapproval(_ document: WorkApprovalItem?) -> Bool {
        document?.editRequiresReapproval == true
    }

    /// "Đã chỉnh sửa bởi Tên lúc HH:mm dd/MM/yyyy" (Vietnam time) when the server sent it.
    static func lastEditedText(_ document: WorkApprovalItem) -> String? {
        guard !document.lastEditedByName.isEmpty, let at = document.lastEditedAt else { return nil }
        return "Đã chỉnh sửa bởi \(document.lastEditedByName) lúc \(formatTimeDate(at))"
    }

    /// HH:mm dd/MM/yyyy in Vietnam time.
    static func formatTimeDate(_ millis: Int64) -> String {
        let value = formatDateTime(millis)
        let parts = value.split(separator: " ")
        guard parts.count == 2 else { return value }
        return "\(parts[1]) \(parts[0])"
    }

    /// The approval decision a return needs: trimmed, required, at most 500 characters.
    static func validateReturnReason(_ raw: String) -> Result<String, ConvexException> {
        let reason = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty {
            return .failure(ConvexException(code: "WORK_RETURN_REASON_INVALID", message: "Vui lòng nhập lý do trả lại."))
        }
        if reason.count > returnReasonMaxLength {
            return .failure(ConvexException(code: "WORK_RETURN_REASON_INVALID", message: "Lý do trả lại tối đa 500 ký tự."))
        }
        return .success(reason)
    }

    /// The only assignee is the creator ("văn thư giao cho chính mình"): the server releases it without
    /// approval, so the form does not require approvers. Any department row means it is not self-only.
    static func isSelfOnlyAssignment(_ assignments: [WorkCreateAssignment], currentUserId: String) -> Bool {
        let me = currentUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !me.isEmpty, !assignments.isEmpty else { return false }
        return assignments.allSatisfy { row in
            let ids = row.userIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return row.isIndividual && !ids.isEmpty && ids.allSatisfy { $0 == me }
        }
    }

    /// Client-side requirement only (UX); the server re-checks with WORK_APPROVER_REQUIRED.
    static func approversRequired(requiresApproval: Bool, assignments: [WorkCreateAssignment], currentUserId: String) -> Bool {
        requiresApproval && !isSelfOnlyAssignment(assignments, currentUserId: currentUserId)
    }

    static func submitTitle(editing: Bool, approvalNeeded: Bool) -> String {
        if editing { return approvalNeeded ? "Lưu và gửi duyệt lại" : "Lưu thay đổi" }
        return approvalNeeded ? "Gửi duyệt" : "Tạo công việc"
    }

    /// Bell / push label for work approval sources (`approval`, `work_approved`, `work_returned`).
    static func notificationLabel(sourceType: String) -> String? {
        switch sourceType {
        case "approval", "document": return "Công việc chờ duyệt"
        case "work_approved": return "Công việc đã duyệt"
        case "work_returned": return "Công việc bị trả lại"
        default: return nil
        }
    }

    /// Notification sources that focus a work document (opened in the Công việc tab).
    static func isDocumentNotification(sourceType: String) -> Bool {
        ["approval", "document", "work_approved", "work_returned"].contains(sourceType)
    }
}

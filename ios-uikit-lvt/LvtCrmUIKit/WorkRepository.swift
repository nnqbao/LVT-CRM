import Foundation
import CryptoKit

struct WorkTaskItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case workItem, personalTask }
    let id: String
    let kind: Kind
    let title: String
    let deadline: String
    var status: String
    let documentContent: String
    let departmentName: String
    let qualityPercent: Int?
    let rejectionReason: String
    let isAdmin: Bool
    let documentTitle: String
    let fileName: String
    let documentId: String
    let fileURL: String
    let privateFile: Bool
    let memberNames: [String]
    let note: String
}

struct WorkCompletionReviewItem: Identifiable, Equatable, Sendable {
    var id: String { workItemId + userId }
    let workItemId: String
    let userId: String
    let userName: String
    let content: String
    let deadline: String
    let departmentName: String
    let note: String
}

struct WorkSnapshot: Equatable, Sendable {
    let assignerMode: String
    let isAdmin: Bool
    let accessLevel: Int
    let tasks: [WorkTaskItem]
    /// Documents I manage ("Việc tôi tạo", from `work:listAdmin`).
    let approvals: [WorkApprovalItem]
    let completionReviews: [WorkCompletionReviewItem]
    let canCreate: Bool
    let isOps: Bool
    let documentTypes: [WorkDocumentType]
    /// Ban giám hiệu "Chờ tôi duyệt" queue (from `work:listMine` approvals, never for admin/mod).
    var approvalQueue: [WorkApprovalItem] = []
    var currentUserId: String = ""
}

enum WorkHelpers {
    static func listTitle(_ document: WorkApprovalItem) -> String {
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let fileName = document.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileName.isEmpty { return fileName }
        let content = document.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? "Công việc" : content
    }

    static func listSubtitle(_ document: WorkApprovalItem) -> String? {
        let title = listTitle(document)
        let content = document.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, content != title else { return nil }
        return content
    }

    static func publicFileURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        guard !trimmed.isEmpty, lowered != "null", lowered != "undefined" else { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return trimmed
    }

    static func jsonString(_ value: Any?) -> String {
        guard let text = value as? String else { return "" }
        return text
    }

    static func hasAttachedFile(_ task: WorkTaskItem) -> Bool {
        !task.documentId.isEmpty && task.privateFile
    }

    static func attachedDocument(_ task: WorkTaskItem) -> WorkApprovalItem {
        WorkApprovalItem(
            id: task.documentId,
            title: task.documentTitle.isEmpty ? task.title : task.documentTitle,
            fileName: task.fileName,
            fileURL: task.fileURL,
            privateFile: task.privateFile,
            content: task.documentContent,
            deadline: task.deadline,
            status: task.status,
            approvalCount: 0,
            approvalTotal: 0,
            myDecision: "",
            assignments: []
        )
    }

    static func needsCompletion(_ status: String) -> Bool {
        ["pending_task", "pending", "overdue", "rejected", "rejected_completion"].contains(status)
    }

    static func orderedTasks(_ tasks: [WorkTaskItem]) -> [WorkTaskItem] {
        tasks.sorted {
            let lhsNeeds = needsCompletion($0.status)
            let rhsNeeds = needsCompletion($1.status)
            if lhsNeeds != rhsNeeds { return lhsNeeds && !rhsNeeds }
            if $0.deadline != $1.deadline { return $0.deadline < $1.deadline }
            return $0.title < $1.title
        }
    }

    static func documentTypes(from result: [String: Any]) -> [WorkDocumentType] {
        ((result["documentTypes"] as? [[String: Any]]) ?? []).compactMap { item in
            let id = (item["_id"] as? String) ?? ""
            let name = (item["name"] as? String) ?? ""
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return WorkDocumentType(id: id, name: name, code: (item["code"] as? String) ?? "")
        }
    }
}

final class WorkRepository: Sendable {
    private let convex: ConvexHttpClient
    private let tokenProvider: @Sendable () -> String?
    private let documentCache = WorkDocumentCache()

    init(convex: ConvexHttpClient, tokenProvider: @escaping @Sendable () -> String?) {
        self.convex = convex
        self.tokenProvider = tokenProvider
    }

    func listMine() async throws -> WorkSnapshot {
        var result = try await convex.query("work:listMine")
        if WorkHelpers.documentTypes(from: result).isEmpty {
            _ = try? await convex.mutation("documentTypes:ensureDefaults", args: [:])
            result = try await convex.query("work:listMine")
        }
        let isAdmin = (result["isAdmin"] as? Bool) ?? false
        let canCreate = (result["canCreate"] as? Bool) ?? false
        let accessLevel = (result["level"] as? Int) ?? 0
        let assignerMode = (result["assignerMode"] as? String) ?? ""
        let currentUserId = (result["userId"] as? String) ?? ""

        var approvals: [WorkApprovalItem] = []
        var completionReviews: [WorkCompletionReviewItem] = []
        var isOps = isAdmin
        if isAdmin || canCreate {
            let adminResult = try await convex.query("work:listAdmin")
            isOps = (adminResult["isOps"] as? Bool) ?? isAdmin
            approvals = (adminResult["documents"] as? [[String: Any]] ?? []).map { document in
                parseApproval(document, currentUserId: currentUserId)
            }
            completionReviews = parseCompletionReviews(
                adminResult["pendingCompletionReviews"] as? [[String: Any]]
            )
        } else {
            completionReviews = parseCompletionReviews(
                result["pendingCompletionReviews"] as? [[String: Any]]
            )
        }
        // Ban giám hiệu may both create work and approve văn thư documents: the queue is separate.
        let approvalQueue = isAdmin ? [] : WorkApprovalDecoding.orderedQueue(
            (result["approvals"] as? [[String: Any]] ?? []).map { document in
                parseApproval(document, currentUserId: currentUserId)
            }
        )

        var tasks: [WorkTaskItem] = []
        for task in result["myTasks"] as? [[String: Any]] ?? [] {
            tasks.append(WorkTaskItem(
                id: (task["_id"] as? String) ?? "",
                kind: .workItem,
                title: (task["content"] as? String) ?? "",
                deadline: (task["deadline"] as? String) ?? "",
                status: (task["status"] as? String) ?? "",
                documentContent: (task["documentContent"] as? String) ?? "",
                departmentName: (task["departmentName"] as? String) ?? "",
                qualityPercent: task["qualityPercent"] as? Int,
                rejectionReason: (task["rejectionReason"] as? String) ?? "",
                isAdmin: isAdmin,
                documentTitle: (task["documentTitle"] as? String) ?? "",
                fileName: (task["fileName"] as? String) ?? "",
                documentId: (task["documentId"] as? String) ?? "",
                fileURL: WorkHelpers.publicFileURL(WorkHelpers.jsonString(task["fileUrl"])) ?? "",
                privateFile: (task["privateFile"] as? Bool) ?? false,
                memberNames: Self.memberNames(from: task),
                note: Self.completionNote(from: task)
            ))
        }
        for task in result["personalTasks"] as? [[String: Any]] ?? [] {
            let title = ((task["title"] as? String)?.nilIfBlank)
                ?? (task["documentContent"] as? String)
                ?? ""
            tasks.append(WorkTaskItem(
                id: (task["_id"] as? String) ?? "",
                kind: .personalTask,
                title: title,
                deadline: (task["deadline"] as? String) ?? "",
                status: (task["status"] as? String) ?? "",
                documentContent: (task["documentContent"] as? String) ?? "",
                departmentName: (task["departmentName"] as? String) ?? "",
                qualityPercent: task["qualityPercent"] as? Int,
                rejectionReason: (task["rejectionReason"] as? String) ?? "",
                isAdmin: isAdmin,
                documentTitle: (task["documentTitle"] as? String) ?? "",
                fileName: (task["fileName"] as? String) ?? "",
                documentId: (task["documentId"] as? String) ?? "",
                fileURL: WorkHelpers.publicFileURL(WorkHelpers.jsonString(task["fileUrl"])) ?? "",
                privateFile: (task["privateFile"] as? Bool) ?? false,
                memberNames: Self.memberNames(from: task, key: "assignees"),
                note: Self.completionNote(from: task)
            ))
        }

        let sortedApprovals = approvals.sorted {
            let lhsPending = WorkApprovalRules.effectiveStatus($0) == "awaiting_approval" || $0.status == "pending"
            let rhsPending = WorkApprovalRules.effectiveStatus($1) == "awaiting_approval" || $1.status == "pending"
            if lhsPending != rhsPending { return lhsPending && !rhsPending }
            return $0.deadline < $1.deadline
        }
        return WorkSnapshot(
            assignerMode: assignerMode,
            isAdmin: isAdmin,
            accessLevel: accessLevel,
            tasks: WorkHelpers.orderedTasks(tasks),
            approvals: sortedApprovals,
            completionReviews: completionReviews,
            canCreate: canCreate,
            isOps: isOps,
            documentTypes: WorkHelpers.documentTypes(from: result),
            approvalQueue: approvalQueue,
            currentUserId: currentUserId
        )
    }

    func formOptions() async throws -> WorkFormOptions {
        var result = try await convex.query("work:formOptions")
        var documentTypes = WorkHelpers.documentTypes(from: result)
        if documentTypes.isEmpty {
            _ = try? await convex.mutation("documentTypes:ensureDefaults", args: [:])
            result = try await convex.query("work:formOptions")
            documentTypes = WorkHelpers.documentTypes(from: result)
        }
        let departments = (result["departments"] as? [[String: Any]] ?? []).map { item in
            WorkFormDepartment(
                id: (item["_id"] as? String) ?? "",
                name: (item["name"] as? String) ?? ""
            )
        }
        return WorkFormOptions.decode(result, documentTypes: documentTypes, departments: departments)
    }

    func createDocument(
        title: String,
        assignments: [WorkCreateAssignment],
        evidence: WorkUploadedEvidence?,
        documentTypeId: String?,
        approverUserIds: [String] = []
    ) async throws -> String {
        let args = WorkCreatePolicy.mutationArgs(
            title: title,
            assignments: assignments,
            evidence: evidence,
            documentTypeId: documentTypeId,
            approverUserIds: approverUserIds
        )
        do {
            let result = try await convex.mutation("work:createDocument", args: args)
            if let token = evidence?.cleanupToken, !token.isEmpty {
                await settleUploadedFile(cleanupToken: token, finalize: true)
            }
            return (result["value"] as? String) ?? (result["_id"] as? String) ?? ""
        } catch {
            if let token = evidence?.cleanupToken, !token.isEmpty {
                await settleUploadedFile(cleanupToken: token, finalize: false)
            }
            throw error
        }
    }

    func updateDocument(
        documentId: String,
        title: String,
        assignments: [WorkCreateAssignment],
        evidence: WorkUploadedEvidence?,
        documentTypeId: String?,
        approverUserIds: [String] = []
    ) async throws {
        var args = WorkCreatePolicy.mutationArgs(
            title: title,
            assignments: assignments,
            evidence: evidence,
            documentTypeId: documentTypeId,
            approverUserIds: approverUserIds
        )
        args["documentId"] = documentId
        do {
            let result = try await convex.mutation("work:updateDocument", args: args)
            if let token = evidence?.cleanupToken, !token.isEmpty {
                await settleUploadedFile(cleanupToken: token, finalize: true)
            }
            await settleCleanupJob(result["cleanupJobId"] as? String)
        } catch {
            if let token = evidence?.cleanupToken, !token.isEmpty {
                await settleUploadedFile(cleanupToken: token, finalize: false)
            }
            throw error
        }
    }

    func deleteDocument(id: String) async throws {
        let result = try await convex.mutation("work:deleteDocument", args: ["documentId": id])
        await settleCleanupJob(result["cleanupJobId"] as? String)
    }

    func complete(
        item: WorkTaskItem,
        qualityPercent: Int? = nil,
        evidence: WorkUploadedEvidence? = nil,
        note: String? = nil,
        documentTypeId: String? = nil
    ) async throws {
        var args: [String: Any] = [:]
        if let qualityPercent { args["qualityPercent"] = qualityPercent }
        if let evidence {
            args["driveFileId"] = evidence.driveFileId
            args["driveChecksum"] = evidence.driveChecksum
            args["cleanupToken"] = evidence.cleanupToken
            args["fileName"] = evidence.fileName
            args["fileType"] = evidence.fileType
            args["fileSize"] = evidence.fileSize
        }
        if let documentTypeId {
            let trimmed = documentTypeId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { args["documentTypeId"] = trimmed }
        }
        let trimmedNote = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            args["note"] = String(trimmedNote.prefix(500))
        }
        switch item.kind {
        case .workItem:
            args["workItemId"] = item.id
            _ = try await convex.mutation("work:completeWorkItem", args: args)
        case .personalTask:
            args["taskId"] = item.id
            _ = try await convex.mutation("work:completePersonalTask", args: args)
        }
        if let token = evidence?.cleanupToken {
            Task {
                await self.settleUploadedFile(cleanupToken: token, finalize: true)
            }
        }
    }

    func uploadEvidence(fileData: Data, fileName: String, mimeType: String) async throws -> WorkUploadedEvidence {
        guard !fileData.isEmpty else {
            throw ConvexException(code: "INVALID_FILE", message: "Tệp đính kèm không có nội dung.")
        }
        guard fileData.count <= 20 * 1024 * 1024 else {
            throw ConvexException(code: "FILE_TOO_LARGE", message: "Dung lượng tệp vượt quá giới hạn 20MB.")
        }
        guard let token = tokenProvider(), !token.isEmpty else {
            throw ConvexException(code: "AUTH_REQUIRED", message: "Vui lòng đăng nhập lại.")
        }
        guard let url = URL(string: "\(ConvexConfig.webURL)/api/files/upload") else {
            throw ConvexException(code: "INVALID_URL", message: "Địa chỉ tải tệp không hợp lệ.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        request.setValue(encodedName, forHTTPHeaderField: "X-File-Name")
        request.setValue("work", forHTTPHeaderField: "X-LVT-Upload-Purpose")
        request.httpBody = fileData
        request.timeoutInterval = 120

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConvexException(code: "WORK_UPLOAD_FAILED", message: "Không thể kết nối đến máy chủ.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorJson = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = (errorJson?["error"] as? String) ?? "WORK_UPLOAD_FAILED:\(http.statusCode)"
            throw ConvexException(code: code, message: "Không thể tải bằng chứng lên. Vui lòng thử lại.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let driveFileId = json["driveFileId"] as? String,
              let cleanupToken = json["cleanupToken"] as? String else {
            throw ConvexException(code: "WORK_UPLOAD_INVALID_RESPONSE", message: "Phản hồi tải tệp không hợp lệ.")
        }
        let driveChecksum = (json["driveChecksum"] as? String) ?? ""
        return WorkUploadedEvidence(
            driveFileId: driveFileId,
            driveChecksum: driveChecksum,
            cleanupToken: cleanupToken,
            fileName: fileName,
            fileType: mimeType,
            fileSize: fileData.count
        )
    }

    private func settleCleanupJob(_ cleanupJobId: String?) async {
        guard let cleanupJobId, !cleanupJobId.isEmpty, cleanupJobId != "null",
              let token = tokenProvider(), !token.isEmpty,
              let encoded = cleanupJobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(ConvexConfig.webURL)/api/files/cleanup-jobs/work/\(encoded)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        _ = try? await URLSession.shared.data(for: request)
    }

    private func settleUploadedFile(cleanupToken: String, finalize: Bool) async {
        guard !cleanupToken.isEmpty,
              let token = tokenProvider(), !token.isEmpty,
              let encodedToken = cleanupToken.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(ConvexConfig.webURL)/api/files/uploads/\(encodedToken)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = finalize ? "POST" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Ban giám hiệu approves (the first approval locks edit/delete for everyone).
    func approveDocument(documentId: String) async throws {
        _ = try await convex.mutation("work:approveDocument", args: ["documentId": documentId])
    }

    /// Ban giám hiệu returns the document to its creator; the reason is required (≤ 500 characters).
    func returnDocument(documentId: String, reason: String) async throws {
        let cleaned: String
        switch WorkApprovalRules.validateReturnReason(reason) {
        case .success(let value): cleaned = value
        case .failure(let error): throw error
        }
        _ = try await convex.mutation("work:rejectDocument", args: ["documentId": documentId, "reason": cleaned])
    }

    func reviewCompletion(
        review: WorkCompletionReviewItem,
        approve: Bool,
        qualityPercent: Int? = nil,
        rejectionReason: String? = nil
    ) async throws {
        var args: [String: Any] = [
            "workItemId": review.workItemId,
            "userId": review.userId,
            "decision": approve ? "approve" : "reject",
        ]
        if let qualityPercent { args["qualityPercent"] = qualityPercent }
        if let rejectionReason, !rejectionReason.isEmpty { args["rejectionReason"] = rejectionReason }
        _ = try await convex.mutation("work:reviewWorkCompletion", args: args)
    }

    func downloadDocument(_ document: WorkApprovalItem) async throws -> URL {
        let sourceURL: URL
        var request: URLRequest
        let sourceIdentity: String
        if document.privateFile,
           let encodedId = document.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "\(ConvexConfig.webURL)/api/files/\(encodedId)"),
           let metadataURL = URL(string: "\(ConvexConfig.webURL)/api/files/\(encodedId)/metadata"),
           let token = tokenProvider(), !token.isEmpty {
            var metadataRequest = URLRequest(url: metadataURL)
            metadataRequest.cachePolicy = .reloadIgnoringLocalCacheData
            metadataRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (metadataData, metadataResponse) = try await URLSession.shared.data(for: metadataRequest)
            guard let metadataHTTP = metadataResponse as? HTTPURLResponse,
                  (200..<300).contains(metadataHTTP.statusCode),
                  let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                  let fileVersion = metadata["fileVersion"] as? String,
                  !fileVersion.isEmpty else {
                throw ConvexException(code: "WORK_FILE_FORBIDDEN", message: "Bạn không còn quyền mở tệp công văn này.")
            }
            sourceURL = url
            request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            sourceIdentity = "private:\(document.id):\(fileVersion)"
        } else if let publicURL = WorkHelpers.publicFileURL(document.fileURL),
                  let url = URL(string: publicURL) {
            sourceURL = url
            request = URLRequest(url: url)
            sourceIdentity = "public:\(document.id):\(publicURL)"
        } else {
            throw ConvexException(code: "WORK_FILE_UNAVAILABLE", message: "Tệp công văn chưa sẵn sàng để mở.")
        }
        if let cached = await documentCache.cachedURL(sourceIdentity: sourceIdentity) {
            return cached
        }
        request.timeoutInterval = 180
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 240
        let (temporaryURL, response) = try await URLSession(configuration: configuration).download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ConvexException(code: "WORK_FILE_DOWNLOAD_FAILED", message: "Không thể tải tệp công văn. Hãy thử lại.")
        }
        let fallbackName = sourceURL.lastPathComponent.isEmpty ? "cong-van" : sourceURL.lastPathComponent
        return try await documentCache.store(
            downloadedURL: temporaryURL,
            sourceIdentity: sourceIdentity,
            fileName: document.fileName.isEmpty ? fallbackName : document.fileName
        )
    }

    private static func completionNote(from value: [String: Any]) -> String {
        if let nested = value["completion"] as? [String: Any] {
            let note = ((nested["note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
        }
        return ((value["note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func memberNames(from value: [String: Any], key: String = "members") -> [String] {
        ((value[key] as? [[String: Any]]) ?? []).compactMap { member in
            let name = ((member["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
            let email = ((member["email"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return email.isEmpty ? nil : email
        }
    }

    private func parseApproval(_ document: [String: Any], currentUserId: String) -> WorkApprovalItem {
        WorkApprovalDecoding.document(
            document,
            currentUserId: currentUserId,
            fileURL: WorkHelpers.publicFileURL(WorkHelpers.jsonString(document["fileUrl"])) ?? ""
        )
    }

    private func parseCompletionReviews(_ items: [[String: Any]]?) -> [WorkCompletionReviewItem] {
        (items ?? []).map { item in
            WorkCompletionReviewItem(
                workItemId: (item["workItemId"] as? String) ?? "",
                userId: (item["userId"] as? String) ?? "",
                userName: (item["userName"] as? String) ?? "",
                content: (item["content"] as? String) ?? "",
                deadline: (item["deadline"] as? String) ?? "",
                departmentName: (item["departmentName"] as? String) ?? "",
                note: (item["note"] as? String) ?? ""
            )
        }
    }
}

private actor WorkDocumentCache {
    private let ttl: TimeInterval = 24 * 60 * 60
    private let maxBytes: Int64 = 1024 * 1024 * 1024
    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("LvtCrmUIKit/work-documents", isDirectory: true)
    }

    func cachedURL(sourceIdentity: String) -> URL? {
        let key = cacheKey(sourceIdentity)
        guard let candidate = existingFile(for: key), isValid(candidate) else {
            removeFiles(withKey: key)
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: candidate.path)
        return candidate
    }

    func store(downloadedURL: URL, sourceIdentity: String, fileName: String) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var cacheDirectory = directory
        try? cacheDirectory.setResourceValues(values)

        let attributes = try fileManager.attributesOfItem(atPath: downloadedURL.path)
        guard (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            throw ConvexException(code: "WORK_FILE_DOWNLOAD_FAILED", message: "Tệp công văn tải về không hợp lệ.")
        }
        let key = cacheKey(sourceIdentity)
        removeFiles(withKey: key)
        let destination = directory.appendingPathComponent("\(key)--\(sanitized(fileName))")
        let staging = directory.appendingPathComponent(".\(key)-\(UUID().uuidString).tmp")
        try fileManager.moveItem(at: downloadedURL, to: staging)
        do {
            try fileManager.moveItem(at: staging, to: destination)
            try fileManager.setAttributes(
                [.creationDate: Date(), .modificationDate: Date()],
                ofItemAtPath: destination.path
            )
            try prune()
            return destination
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func existingFile(for key: String) -> URL? {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return files.first { $0.lastPathComponent.hasPrefix("\(key)--") }
    }

    private func isValid(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0,
              let created = attributes[.creationDate] as? Date else { return false }
        return Date().timeIntervalSince(created) < ttl
    }

    private func prune() throws {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var entries: [(URL, Int64, Date)] = []
        for file in files {
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular else { continue }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let created = attributes[.creationDate] as? Date ?? .distantPast
            if size <= 0 || Date().timeIntervalSince(created) >= ttl {
                try? fileManager.removeItem(at: file)
                continue
            }
            entries.append((file, size, attributes[.modificationDate] as? Date ?? created))
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        for entry in entries.sorted(by: { $0.2 < $1.2 }) where total > maxBytes {
            try? fileManager.removeItem(at: entry.0)
            total -= entry.1
        }
    }

    private func removeFiles(withKey key: String) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(key)--") {
            try? fileManager.removeItem(at: file)
        }
    }

    private func cacheKey(_ sourceIdentity: String) -> String {
        SHA256.hash(data: Data(sourceIdentity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func sanitized(_ fileName: String) -> String {
        let value = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return value.isEmpty ? "cong-van" : String(value.suffix(180))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

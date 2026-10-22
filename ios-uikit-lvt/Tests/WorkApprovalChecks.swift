// extra-sources: NotificationModels
import Foundation

/// NotificationModels needs the chat kind; the real enum lives in a UIKit file.
enum ChatKind: Equatable, Sendable { case duty, work, group }

/// Offline checks for Ban giám hiệu work approval (2.1.0): `documentView` decoding, form options flags,
/// mutation payloads, state rules (lock, unreleased, return reason, self-only), error wording, notification
/// routing and the "?" guide URLs. Injected fixtures only: no network, credentials or app launch.
@main
struct WorkApprovalChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }

        // 2026-10-22 14:05 Asia/Ho_Chi_Minh = 07:05Z.
        let decidedAt: Int64 = 1_792_652_700_000
        func documentRow(
            status: String,
            approved: [String] = [],
            rejected: [String] = [],
            extra: [String: Any] = [:]
        ) -> [String: Any] {
            let approvers: [[String: Any]] = ["bgh1", "bgh2"].map { id in
                [
                    "_id": id, "name": id == "bgh1" ? "Hiệu trưởng A" : "Hiệu phó B", "email": "\(id)@x", "level": 5,
                    "approved": approved.contains(id), "rejected": rejected.contains(id),
                    "decidedAt": (approved + rejected).contains(id) ? NSNumber(value: decidedAt) : NSNull(),
                    "reason": rejected.contains(id) ? "Thiếu hạn chót" : "",
                ]
            }
            var row: [String: Any] = [
                "_id": "doc1", "title": "Kế hoạch tháng 11", "fileName": "", "fileUrl": NSNull(), "privateFile": false,
                "content": "Nộp báo cáo", "deadline": "2026-11-05", "status": status,
                "approvalCount": approved.count, "approvalTotal": 2, "approvers": approvers,
                "requiresApproval": true, "approvalLocked": !approved.isEmpty,
                "returnReason": rejected.isEmpty ? "" : "Thiếu hạn chót",
                "submittedAt": NSNumber(value: decidedAt - 3_600_000), "creatorName": "Văn thư C", "creatorRole": "moderator",
                "canEdit": approved.isEmpty, "canDelete": approved.isEmpty,
                "assignments": [[
                    "_id": "item1", "type": "department", "departmentId": "dep1", "departmentName": "Tổ Toán",
                    "content": "Nộp báo cáo", "deadline": "2026-11-05", "status": "in_progress",
                    "members": [["_id": "u1", "name": "Giáo viên D", "status": "pending_task"]],
                ]],
            ]
            for (key, value) in extra { row[key] = value }
            return row
        }

        // Decoding: approvers, decisions, flags, my decision.
        let pending = WorkApprovalDecoding.document(
            documentRow(status: "pending", approved: ["bgh1"], extra: ["workStatus": "awaiting_approval", "awaitingMyDecision": true, "canReject": false]),
            currentUserId: "bgh1",
            fileURL: ""
        )
        check(pending.approvers.map(\.id) == ["bgh1", "bgh2"] && pending.approvers[0].approved && !pending.approvers[1].approved, "Approver decisions decoded")
        check(pending.approvers[0].decidedAt == decidedAt && pending.approvers[1].decidedAt == nil, "Nullable decision time")
        check(pending.myDecision == "approved" && pending.approvalLocked && pending.requiresApproval, "Flags + my decision")
        check(pending.awaitingMyDecision && !pending.canReject && pending.workStatus == "awaiting_approval", "Queue flags")
        check(pending.submittedAt == decidedAt - 3_600_000 && pending.creatorRole == "moderator", "Submission + creator")
        let legacy = WorkApprovalDecoding.document(["_id": "old", "status": "approved", "approvalCount": 0, "approvalTotal": 0], currentUserId: "", fileURL: "")
        check(!legacy.requiresApproval && legacy.approvers.isEmpty && !legacy.approvalLocked && legacy.submittedAt == nil, "Legacy document without approval fields")
        check(WorkApprovalDecoding.document(["_id": "x", "status": "pending", "approvalLocked": 1], currentUserId: "", fileURL: "").approvalLocked == false, "Non-boolean flag is not trusted")

        // Display: labels, progress, approver chips, return reason, creator.
        check(WorkApprovalRules.creatorStatusText(pending) == "Chờ duyệt · 1/2", "Creator sees Chờ duyệt x/y")
        check(WorkApprovalRules.progressText(pending) == "Ban giám hiệu duyệt 1/2", "Progress text")
        check(WorkApprovalRules.approverDecisionLabel(pending.approvers[0]) == "Đã duyệt 22/10/2026 14:05", "Decision time in Vietnam time")
        check(WorkApprovalRules.approverDecisionLabel(pending.approvers[1]) == "Chờ duyệt", "Waiting approver")
        check(WorkApprovalRules.creatorLabel(pending) == "Người tạo: Văn thư C (Văn thư)", "Creator label")
        check(WorkApprovalRules.queueStatusText(pending) == "Chờ bạn duyệt", "Queue: awaiting")
        let returned = WorkApprovalDecoding.document(
            documentRow(status: "rejected", rejected: ["bgh2"], extra: ["workStatus": "approval_returned"]),
            currentUserId: "bgh2",
            fileURL: ""
        )
        check(WorkApprovalRules.creatorStatusText(returned) == "Bị trả lại · 0/2", "Returned status")
        check(WorkApprovalRules.returnReasonText(returned) == "Lý do trả lại: Thiếu hạn chót", "Return reason shown")
        check(WorkApprovalRules.returnReasonText(pending) == nil, "No reason while pending")
        check(WorkApprovalRules.approverDecisionLabel(returned.approvers[1]) == "Trả lại 22/10/2026 14:05", "Returned chip")
        check(WorkApprovalRules.queueStatusText(returned) == "Đã trả lại", "Queue: returned")
        let released = WorkApprovalDecoding.document(
            documentRow(status: "approved", approved: ["bgh1", "bgh2"], extra: ["workStatus": "in_progress"]),
            currentUserId: "bgh2",
            fileURL: ""
        )
        check(WorkApprovalRules.creatorStatusText(released) == "Đang thực hiện", "Released shows progress")
        check(WorkApprovalRules.queueStatusText(released) == "Đã duyệt", "Queue: released")
        var partial = pending
        partial.awaitingMyDecision = false
        check(WorkApprovalRules.queueStatusText(partial) == "Bạn đã duyệt · chờ người khác", "Queue: partial approval")

        // Unreleased assignments read "Chờ duyệt (chưa giao)".
        check(WorkApprovalRules.isUnreleased(pending) && WorkApprovalRules.isUnreleased(returned) && !WorkApprovalRules.isUnreleased(released), "Unreleased rule")
        check(WorkApprovalRules.statusLabel(WorkApprovalRules.assignmentDisplayStatus(pending, pending.assignments[0])) == "Chờ duyệt (chưa giao)", "Unreleased assignment label")
        check(WorkApprovalRules.statusLabel(WorkApprovalRules.assignmentDisplayStatus(released, released.assignments[0])) == "Đang thực hiện", "Released assignment label")
        check(WorkApprovalRules.statusLabel(WorkApprovalRules.assignmentDisplayStatus(legacy, WorkDocumentAssignment(id: "", departmentName: "", content: "", deadline: "", status: "", members: []))) == "Chưa giao việc", "Empty status")

        // Lock: the first approval hides edit/delete for everyone, admin/mod included.
        check(!WorkApprovalRules.showsEdit(pending, isOps: true) && !WorkApprovalRules.showsDelete(pending, isOps: true), "Approval lock beats ops")
        check(WorkApprovalRules.lockedMessage(pending, isOps: true) == "Đã có người duyệt · Không thể sửa hoặc xóa", "Approval lock wording")
        check(WorkApprovalRules.showsEdit(returned, isOps: false) && WorkApprovalRules.showsDelete(returned, isOps: false), "Returned stays editable")
        var submitted = returned
        submitted.canEdit = false
        submitted.canDelete = false
        check(!WorkApprovalRules.showsEdit(submitted, isOps: false) && WorkApprovalRules.showsEdit(submitted, isOps: true), "Ops keep edit after a submission")
        check(WorkApprovalRules.lockedMessage(submitted, isOps: false) == "Đã có người nộp · Không thể sửa hoặc xóa", "Submission lock wording")

        // List status: the aggregate workStatus wins over the document status (list tabs use it).
        check(WorkApprovalRules.effectiveStatus(pending) == "awaiting_approval" && WorkApprovalRules.effectiveStatus(legacy) == "approved", "Effective status")

        // Queue order: awaiting first, newest submission next.
        var older = released
        older.submittedAt = 1
        let queue = WorkApprovalDecoding.orderedQueue([older, released, pending])
        check(queue.map(\.awaitingMyDecision) == [true, false, false] && queue[1].submittedAt == released.submittedAt, "Queue order")

        // Return reason: required, trimmed, ≤ 500.
        if case .success(let reason) = WorkApprovalRules.validateReturnReason("  Thiếu hạn  ") { check(reason == "Thiếu hạn", "Trimmed reason") } else { check(false, "Valid reason") }
        if case .failure(let error) = WorkApprovalRules.validateReturnReason("   ") { check(error.message == "Vui lòng nhập lý do trả lại.", "Empty reason") } else { check(false, "Empty reason rejected") }
        if case .failure = WorkApprovalRules.validateReturnReason(String(repeating: "x", count: 501)) { check(true, "Long reason rejected") } else { check(false, "Long reason rejected") }
        if case .success = WorkApprovalRules.validateReturnReason(String(repeating: "x", count: 500)) { check(true, "500 allowed") } else { check(false, "500 allowed") }

        // Form options: server flags, never derived from levels.
        let options = WorkFormOptions.decode([
            "canCreate": true, "isOps": true, "requiresApproval": true, "canAssignDepartments": true,
            "users": [["_id": "u1", "name": "Giáo viên D", "departmentName": "Tổ Toán", "level": 1]],
            "approvers": [["_id": "bgh1", "name": "Hiệu trưởng A", "level": 5, "positionName": "Hiệu trưởng"], ["name": "no id"]],
        ], documentTypes: [], departments: [])
        check(options.requiresApproval && options.canAssignDepartments && options.approvers.map(\.id) == ["bgh1"] && options.approvers[0].positionName == "Hiệu trưởng", "Approver options")
        let bgh = WorkFormOptions.decode(["canCreate": true, "isOps": false, "requiresApproval": false, "canAssignDepartments": true, "users": [], "approvers": []], documentTypes: [], departments: [])
        check(!bgh.requiresApproval && bgh.canAssignDepartments && bgh.approvers.isEmpty, "Ban giám hiệu: departments, no approval")
        let lead = WorkFormOptions.decode(["canCreate": true, "isOps": false, "users": []], documentTypes: [], departments: [])
        check(!lead.canAssignDepartments && !lead.requiresApproval, "Missing flags fall back safely")
        check(WorkFormOptions.decode(["isOps": true], documentTypes: [], departments: []).canAssignDepartments, "Older server: ops assign departments")

        // Approver requirement and self-only rule (server decides; the client only relaxes the UX).
        let others = [WorkCreateAssignment(type: "individual", departmentId: "", userIds: ["u1"], content: "a", deadline: "2026-11-05")]
        let selfOnly = [WorkCreateAssignment(type: "individual", departmentId: "", userIds: ["me"], content: "a", deadline: "2026-11-05")]
        let department = [WorkCreateAssignment(type: "department", departmentId: "dep1", userIds: [], content: "a", deadline: "2026-11-05")]
        check(WorkApprovalRules.isSelfOnlyAssignment(selfOnly, currentUserId: "me"), "Self-only")
        check(!WorkApprovalRules.isSelfOnlyAssignment(selfOnly + others, currentUserId: "me") && !WorkApprovalRules.isSelfOnlyAssignment(department, currentUserId: "me"), "Mixed / department is not self-only")
        check(!WorkApprovalRules.isSelfOnlyAssignment(selfOnly, currentUserId: ""), "Unknown user is not self-only")
        check(WorkApprovalRules.approversRequired(requiresApproval: true, assignments: others, currentUserId: "me"), "Ops for others need approvers")
        check(!WorkApprovalRules.approversRequired(requiresApproval: true, assignments: selfOnly, currentUserId: "me"), "Ops for self do not")
        check(!WorkApprovalRules.approversRequired(requiresApproval: false, assignments: others, currentUserId: "me"), "Non-ops never")
        check(WorkCreatePolicy.validate(title: "Việc", assignments: others, approversRequired: true, approverCount: 0) == "Vui lòng chọn ít nhất một người duyệt thuộc Ban giám hiệu.", "Approver required message")
        check(WorkCreatePolicy.validate(title: "Việc", assignments: others, approversRequired: true, approverCount: 1) == nil, "Approver chosen")
        check(WorkApprovalRules.submitTitle(editing: false, approvalNeeded: true) == "Gửi duyệt", "Gửi duyệt")
        check(WorkApprovalRules.submitTitle(editing: true, approvalNeeded: true) == "Lưu và gửi duyệt lại", "Lưu và gửi duyệt lại")
        check(WorkApprovalRules.submitTitle(editing: false, approvalNeeded: false) == "Tạo công việc", "Tạo")

        // Payload: approverUserIds sent when provided (deduplicated), omitted otherwise.
        let args = WorkCreatePolicy.mutationArgs(title: " Việc ", assignments: others + department, evidence: nil, documentTypeId: nil, approverUserIds: ["bgh1", " bgh1 ", "", "bgh2"])
        check(args["approverUserIds"] as? [String] == ["bgh1", "bgh2"], "Approver ids deduplicated")
        check(args["title"] as? String == "Việc" && args["documentTypeId"] == nil, "Title trimmed, no type")
        let rows = args["assignments"] as? [[String: Any]] ?? []
        check(rows.count == 2 && rows[0]["userIds"] as? [String] == ["u1"] && rows[1]["departmentId"] as? String == "dep1" && rows[1]["userIds"] == nil, "Assignment payload")
        check(WorkCreatePolicy.mutationArgs(title: "x", assignments: selfOnly, evidence: nil, documentTypeId: nil, approverUserIds: [])["approverUserIds"] == nil, "No approvers omitted")

        // Error wording (web appErrorMessage.js), never the generic FORBIDDEN text.
        let expected: [(String, String)] = [
            ("WORK_APPROVER_REQUIRED", "Công việc do Văn thư/Quản trị tạo cần chọn ít nhất một người duyệt thuộc Ban giám hiệu."),
            ("WORK_RETURN_REASON_INVALID", "Vui lòng nhập lý do trả lại (tối đa 500 ký tự)."),
            ("WORK_ASSIGNEE_BGH_FORBIDDEN", "Văn thư không thể giao công việc cho Ban giám hiệu."),
            ("WORK_ASSIGNEE_OPS_FORBIDDEN", "Chỉ được giao công việc cho Quản trị viên/Văn thư khác cùng phòng ban."),
            ("MODERATOR_DEPARTMENT_SCOPE", "Moderator chỉ được thao tác trong phòng ban được gán."),
            ("WORK_DOCUMENT_ALREADY_DECIDED", "Công việc này đã được duyệt hoặc trả lại, không thể đổi quyết định."),
            ("WORK_APPROVER_FORBIDDEN", "Bạn không nằm trong danh sách duyệt công việc này."),
            ("WORK_DOCUMENT_IMMUTABLE", "Công việc đã có người duyệt hoặc người nộp nên không thể sửa hoặc xóa."),
            ("INVALID_WORK_APPROVER", "Người duyệt phải là thành viên Ban giám hiệu (cấp 4 hoặc 5 sao) đang hoạt động, không phải Administrator/Moderator."),
            ("WORK_DEPARTMENT_FORBIDDEN", "Chỉ Văn thư và Ban giám hiệu được giao việc cho cả phòng ban."),
            ("WORK_ASSIGNEE_NOT_SUBORDINATE", "Chỉ được giao cho người có cấp thấp hơn bạn. Tổ trưởng/tổ phó chỉ giao trong phòng ban của mình."),
            ("ADMIN_USE_MANAGEMENT", "Administrator/Moderator quản lý công việc, không duyệt thay Ban giám hiệu."),
            ("WORK_NOT_APPROVED", "Công việc chưa được Ban giám hiệu duyệt đủ."),
        ]
        for (code, message) in expected {
            let raw = "[CONVEX M(work:createDocument)] Uncaught Error: \(code)\n    at handler"
            check(ConvexHttpClient.extractCode(raw) == code, "Extract \(code)")
            check(ConvexHttpClient.humanize(raw) == message, "Message for \(code)")
        }
        check(WorkCreatePolicy.actionError(raw: "WORK_DOCUMENT_IMMUTABLE x", deleting: true, fallback: "f") == "Công việc đã có người duyệt hoặc người nộp nên không thể sửa hoặc xóa.", "Delete lock message")
        check(WorkCreatePolicy.actionError(raw: "network", deleting: true, fallback: "f") == "Không thể xóa công văn lúc này.", "Delete fallback")
        check(ConvexHttpClient.humanize("DUTY_CHAT_FORBIDDEN") == "Bạn không có quyền trao đổi mục này.", "Other codes unchanged")

        // Notifications: bell labels and routing to the Công việc document.
        check(WorkApprovalRules.notificationLabel(sourceType: "approval") == "Công việc chờ duyệt", "Approval label")
        check(WorkApprovalRules.notificationLabel(sourceType: "work_approved") == "Công việc đã duyệt", "Approved label")
        check(WorkApprovalRules.notificationLabel(sourceType: "work_returned") == "Công việc bị trả lại", "Returned label")
        check(WorkApprovalRules.notificationLabel(sourceType: "work_chat") == nil, "Chat untouched")
        for sourceType in ["approval", "work_approved", "work_returned"] {
            let push = NotificationDestination.from(userInfo: ["kind": "work", "sourceType": sourceType, "sourceId": "doc1"])
            check(push?.route == .work && push?.sourceId == "doc1" && push?.opensChat == false && push?.opensTodos == false, "Push \(sourceType) opens Công việc")
            let bell = NotificationDestination.from(url: URL(string: "lvtcrm://notification?kind=work&sourceType=\(sourceType)&sourceId=doc1&key=work:\(sourceType):doc1:1")!)
            check(bell?.route == .work && bell?.notificationKey == "work:\(sourceType):doc1:1", "Bell \(sourceType) opens Công việc")
            check(WorkApprovalRules.isDocumentNotification(sourceType: sourceType), "Document source \(sourceType)")
        }

        // "?" guide URLs (web GUIDE_ANCHORS + embed).
        check(HelpGuide.url(for: .work)?.absoluteString == "https://lvt.vscgroup.io.vn/huong-dan-su-dung.html?embed=1#menu-cong-viec", "Work guide URL")
        check(HelpGuide.url(for: .overview)?.absoluteString == "https://lvt.vscgroup.io.vn/huong-dan-su-dung.html?embed=1", "Overview guide URL")
        check(HelpGuide.url(for: .boarding, webBase: "https://example.test/")?.absoluteString == "https://example.test/huong-dan-su-dung.html?embed=1#bt-ban-tru", "Custom base")
        check(HelpGuide.url(for: .work, webBase: "javascript:alert(1)") == nil, "Only http(s)")
        let anchors: [HelpGuide.Topic: String] = [
            .notifications: "tb-thong-bao", .chat: "td-trao-doi", .duties: "menu-lich-cong-tac", .homeroom: "menu-lop-chu-nhiem",
            .attendance: "menu-diem-danh", .profile: "tai-khoan-ca-nhan", .reports: "menu-bao-cao", .boarding: "bt-ban-tru",
        ]
        for (topic, anchor) in anchors { check(topic.rawValue == anchor, "Anchor \(anchor)") }

        print("WorkApprovalChecks: \(checks) checks passed")
    }
}

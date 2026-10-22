import Foundation

struct ConvexException: Error, LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }

    init(code: String, message: String? = nil) {
        self.code = code
        self.message = message ?? ConvexHttpClient.humanize(code)
    }
}

actor ConvexHttpClient {
    private let baseURL: String
    private let tokenProvider: @Sendable () -> String?
    private let refreshCredentialsProvider: @Sendable () -> CredentialSnapshot?
    private let onTokensRefreshed: @Sendable (CredentialSnapshot, String, String) -> Bool
    private let session: URLSession
    private let importSession: URLSession
    private var inFlightRefresh: Task<String?, Never>?

    init(
        baseURL: String,
        tokenProvider: @escaping @Sendable () -> String?,
        refreshCredentialsProvider: @escaping @Sendable () -> CredentialSnapshot?,
        onTokensRefreshed: @escaping @Sendable (CredentialSnapshot, String, String) -> Bool,
        sessionOverride: URLSession? = nil
    ) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.tokenProvider = tokenProvider
        self.refreshCredentialsProvider = refreshCredentialsProvider
        self.onTokensRefreshed = onTokensRefreshed
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        session = sessionOverride ?? URLSession(configuration: configuration)
        importSession = sessionOverride ?? URLSession(configuration: configuration, delegate: UploadRedirectGuard(), delegateQueue: nil)
    }

    func query(_ path: String, args: [String: Any] = [:], authenticated: Bool = true) async throws -> [String: Any] {
        try await call(kind: "query", path: path, args: args, authenticated: authenticated)
    }

    func mutation(_ path: String, args: [String: Any] = [:], authenticated: Bool = true) async throws -> [String: Any] {
        try await call(kind: "mutation", path: path, args: args, authenticated: authenticated)
    }
    func importCall(_ kind: String, path: String, args: [String: Any]) async throws -> [String: Any] {
        try await call(kind: kind, path: path, args: args, authenticated: true, noRetry: true)
    }
    static func validateHomeroomAcknowledgment(_ path: String, envelope: [String: Any], statusCode: Int) throws {
        guard (200..<300).contains(statusCode), envelope["status"] as? String == "success", let value = envelope["value"] else { throw ConvexException(code: "INVALID_MUTATION_ACK") }
        if ["students:updateContacts", "students:removeGuardian"].contains(path) {
            guard value is NSNull else { throw ConvexException(code: "INVALID_MUTATION_ACK") }
        } else if path == "students:upsertGuardian" {
            guard let id = value as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConvexException(code: "INVALID_MUTATION_ACK") }
        } else { guard value is [String: Any] else { throw ConvexException(code: "INVALID_MUTATION_ACK") } }
    }

    func action(_ path: String, args: [String: Any] = [:], authenticated: Bool = true) async throws -> [String: Any] {
        try await call(kind: "action", path: path, args: args, authenticated: authenticated)
    }

    func actionWithToken(_ path: String, args: [String: Any], accessToken: String) async throws -> [String: Any] {
        try await call(kind: "action", path: path, args: args, authenticated: true, accessTokenOverride: accessToken)
    }

    func mutationWithToken(_ path: String, args: [String: Any], accessToken: String) async throws -> [String: Any] {
        try await call(kind: "mutation", path: path, args: args, authenticated: true, accessTokenOverride: accessToken)
    }

    private func call(
        kind: String,
        path: String,
        args: [String: Any],
        authenticated: Bool,
        retried: Bool = false,
        accessTokenOverride: String? = nil,
        noRetry: Bool = false
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/api/\(kind)") else {
            throw ConvexException(code: "INVALID_URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "path": path,
            "args": args,
            "format": "json",
        ])

        let requestToken = authenticated ? (accessTokenOverride ?? tokenProvider()) : nil
        if authenticated, let requestToken, !requestToken.isEmpty {
            request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await (noRetry ? importSession : session).data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !noRetry, authenticated, accessTokenOverride == nil, statusCode == 401, !retried,
           let refreshed = await tryRefresh(failedAccessToken: requestToken) {
            return try await call(
                kind: kind, path: path, args: args, authenticated: true,
                retried: true, accessTokenOverride: refreshed
            )
        }

        let json = try parseJSONObject(data)
        if (json["status"] as? String) == "success" {
            if noRetry { try Self.validateImportEnvelope(path, envelope: json, statusCode: statusCode) }
            if kind == "mutation", ["students:updateContacts", "students:removeGuardian", "students:upsertGuardian", "studentAttendance:setDisposition"].contains(path) {
                try Self.validateHomeroomAcknowledgment(path, envelope: json, statusCode: statusCode)
            }
            return unwrapValue(json["value"])
        }
        let errorMessage = (json["errorData"] as? String)?.nilIfBlank
            ?? (json["errorMessage"] as? String)?.nilIfBlank
            ?? (json["error"] as? String)?.nilIfBlank
            ?? "CONVEX_ERROR"
        let unauthorized = statusCode == 401
            || errorMessage.localizedCaseInsensitiveContains("Unauthenticated")
            || errorMessage.localizedCaseInsensitiveContains("Authentication")
        if !noRetry, authenticated, accessTokenOverride == nil, unauthorized, !retried,
           let refreshed = await tryRefresh(failedAccessToken: requestToken) {
            return try await call(
                kind: kind, path: path, args: args, authenticated: true,
                retried: true, accessTokenOverride: refreshed
            )
        }
        throw ConvexException(code: noRetry ? Self.extractImportCode(errorMessage) : Self.extractCode(errorMessage), message: noRetry ? Self.humanizeImport(errorMessage) : Self.humanize(errorMessage))
    }

    private func tryRefresh(failedAccessToken: String?) async -> String? {
        if let inFlightRefresh {
            return await inFlightRefresh.value
        }
        let task = Task { await self.performRefresh(failedAccessToken: failedAccessToken) }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }
    static func validateImportEnvelope(_ path: String, envelope: [String: Any], statusCode: Int) throws {
        let stringPaths = ["studentRosterImport:generateUploadUrl", "homeroomClasses:create", "homeroomClasses:assignUser", "homeroomClasses:transferStudent", "students:create"]
        let nullPaths = ["homeroomClasses:update", "homeroomClasses:archive", "homeroomClasses:restore", "homeroomClasses:withdrawStudent"]
        let correct = stringPaths.contains(path) ? envelope["value"] is String : nullPaths.contains(path) ? envelope["value"] is NSNull : envelope["value"] is [String: Any]
        guard (200..<300).contains(statusCode), envelope["status"] as? String == "success", correct else { throw ConvexException(code: "IMPORT_UNCERTAIN") }
    }

    private func performRefresh(failedAccessToken: String?) async -> String? {
        guard let expected = refreshCredentialsProvider() else { return nil }
        if let failedAccessToken, !failedAccessToken.isEmpty, expected.accessToken != failedAccessToken {
            return expected.accessToken
        }
        guard let failedAccessToken, !failedAccessToken.isEmpty else { return nil }
        do {
            guard let url = URL(string: "\(baseURL)/api/action") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "path": "auth:signIn",
                "args": ["refreshToken": expected.refreshToken],
                "format": "json",
            ])
            let (data, _) = try await session.data(for: request)
            let json = try parseJSONObject(data)
            guard (json["status"] as? String) == "success",
                  let value = json["value"] as? [String: Any],
                  let tokens = value["tokens"] as? [String: Any],
                  let access = tokens["token"] as? String,
                  let refresh = tokens["refreshToken"] as? String else { return nil }
            return onTokensRefreshed(expected, access, refresh) ? access : nil
        } catch {
            return nil
        }
    }

    private func unwrapValue(_ value: Any?) -> [String: Any] {
        switch value {
        case nil, is NSNull: return [:]
        case let object as [String: Any]: return object
        case let array as [Any]: return ["items": array]
        case let bool as Bool: return ["ok": bool]
        case let number as NSNumber: return ["value": number]
        case let string as String: return ["value": string]
        default: return ["value": "\(value!)"]
        }
    }

    private func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConvexException(code: "INVALID_JSON", message: "Phản hồi Convex không hợp lệ.")
        }
        return object
    }

    static func extractImportCode(_ message: String) -> String {
        let management = ["CLASS_CODE_TAKEN", "INVALID_CLASS_CODE", "INVALID_GRADE_LEVEL", "SCHOOL_YEAR_LOCKED", "STUDENT_CODE_EXISTS", "INVALID_STUDENT_CODE", "ENROLLMENT_NOT_FOUND", "ENROLLMENT_NOT_ACTIVE", "ENROLLMENT_YEAR_MISMATCH", "DUPLICATE_ACTIVE_ENROLLMENT", "TRANSFER_BEFORE_START", "WITHDRAW_BEFORE_START", "INVALID_TRANSFER", "INVALID_REASON", "HOMEROOM_TEACHER_OVERLAP", "HOMEROOM_TEACHER_ALREADY_ASSIGNED", "ASSIGNMENT_BEFORE_START", "INVALID_ASSIGNMENT_TYPE", "INVALID_ASSIGNMENT_SCOPE", "USER_NOT_FOUND", "IMPORT_VALIDATION_FAILED", "IMPORT_UPLOAD_ALREADY_COMMITTED", "IMPORT_UPLOAD_IN_PROGRESS", "STUDENT_ENROLLED_OTHER_CLASS"]
        if let code = management.first(where: { message.contains($0) }) { return code }
        let known = ["INVALID_IMPORT_FILE", "IMPORT_FILE_TOO_LARGE", "IMPORT_FILE_EMPTY", "IMPORT_TOO_MANY_ROWS", "IMPORT_UPLOAD_EXPIRED", "IMPORT_UPLOAD_NOT_FOUND", "SCHOOL_YEAR_NOT_FOUND", "INVALID_DATE", "HOMEROOM_MENU_HIDDEN", "HOMEROOM_SCOPE_FORBIDDEN"]
        return known.first { message.contains($0) } ?? extractCode(message)
    }
    static func humanizeImport(_ message: String) -> String {
        let code = extractImportCode(message)
        switch code {
        case "INVALID_IMPORT_FILE", "IMPORT_FILE_EMPTY", "IMPORT_FILE_TOO_LARGE": return "File Excel không hợp lệ, rỗng hoặc quá 2 MiB. Kiểm tra file .xlsx danh sách học sinh."
        case "IMPORT_TOO_MANY_ROWS": return "File vượt quá số dòng cho phép; chuẩn bị file nhỏ hơn."
        case "IMPORT_UPLOAD_EXPIRED": return "Bản đăng ký đã quá hạn; không thể ghi. File không được ứng dụng tự xóa."
        case "IMPORT_UPLOAD_NOT_FOUND": return "Không tìm thấy bản đăng ký; không tự đăng ký/gửi lại file."
        case "SCHOOL_YEAR_NOT_FOUND", "INVALID_DATE": return "Năm/ngày học không hợp lệ; chọn lại ngữ cảnh."
        case "HOMEROOM_MENU_HIDDEN": return "Bạn không có quyền dùng Lớp chủ nhiệm."
        default: return humanize(message)
        }
    }
    static func extractCode(_ message: String) -> String {
        let known = workCodes + boardingCodes + schoolFeedbackCodes + [
            "INVALID_PHONE", "INVALID_NAME", "INVALID_TEXT", "INVALID_DISPOSITION_NOTE", "INVALID_DISPOSITION", "CORRECTION_REASON_REQUIRED", "GUARDIAN_LIMIT", "ATTENDANCE_DAY_NOT_FOUND", "CLASS_NOT_FOUND", "STUDENT_NOT_FOUND", "GUARDIAN_NOT_FOUND", "CLASS_ARCHIVED", "DISPOSITION_NOT_ABSENT",
            "INVALID_CREDENTIALS", "InvalidAccountId", "InvalidSecret", "Invalid credentials", "USER_NOT_ACTIVE",
            "ACCOUNT_LOCKED", "PASSWORD_TOO_SHORT", "PASSWORD_CHANGE_FAILED", "PASSWORD_CHANGED_SYNC_PENDING",
            "PASSWORD_CHANGE_REQUIRED", "PASSWORD_RESET_FAILED", "PASSWORD_RESET_EMAIL_FAILED",
            "MAIL_NOT_CONFIGURED", "MAIL_AUTH_FAILED", "PUBLIC_SIGNUP_DISABLED", "INVALID_EMAIL",
            "INVALID_AUTH_FLOW",
            "DUTY_WEEK_MANAGER_REQUIRED", "DUTY_WEEK_REVIEWER_REQUIRED", "DUTY_WEEK_ALREADY_SUBMITTED",
            "DUTY_WEEK_NOTHING_TO_SUBMIT", "DUTY_WEEK_NOT_SUBMITTED", "DUTY_WEEK_CHANGED",
            "DUTY_WEEK_RETURN_NOTE_REQUIRED", "DUTY_WEEK_RETURN_NOTE_TOO_LONG", "DUTY_UPDATE_FORBIDDEN", "DUTY_NOT_FOUND",
            "INVALID_DUTY_TITLE", "INVALID_CONTENT", "INVALID_LOCATION", "INVALID_OTHER_PARTICIPANTS",
            "INVALID_PARTICIPANT", "INVALID_DEPARTMENT", "END_BEFORE_START",
            "DUTY_CHAT_EMPTY", "WORK_CHAT_EMPTY", "DUTY_CHAT_TOO_LONG", "WORK_CHAT_TOO_LONG",
            "DUTY_CHAT_RECALL_TOO_LATE", "WORK_CHAT_RECALL_TOO_LATE",
            "DUTY_CHAT_RECALL_FORBIDDEN", "WORK_CHAT_RECALL_FORBIDDEN",
            "DUTY_CHAT_FORBIDDEN", "WORK_CHAT_FORBIDDEN",
            "WORK_DOCUMENT_IMMUTABLE", "WORK_UPDATE_FORBIDDEN", "WORK_DOCUMENT_NOT_FOUND",
            "FORBIDDEN", "UNAUTHENTICATED", "CANNOT_REVOKE_CURRENT_SESSION",
            "SESSION_NOT_FOUND", "DOCUMENT_TYPE_REQUIRED", "INVALID_DOCUMENT_TYPE", "SESSION_TIMEOUT",
            "INVALID_AVATAR_FILE", "AVATAR_FILE_TOO_LARGE", "AVATAR_UPLOAD_NOT_FOUND", "AVATAR_NOT_FOUND",
            "AVATAR_UPLOAD_FAILED",
        ]
        return known.first { message.localizedCaseInsensitiveContains($0) } ?? message
    }

    /// Công việc codes (web `appErrorMessage.js`). Longer codes first: matching is by substring.
    static let workCodes = [
        "WORK_ASSIGNEE_BGH_FORBIDDEN", "WORK_ASSIGNEE_OPS_FORBIDDEN", "WORK_ASSIGNEE_NOT_SUBORDINATE",
        "WORK_APPROVER_REQUIRED", "WORK_APPROVERS_REQUIRED", "INVALID_WORK_APPROVER", "WORK_APPROVER_FORBIDDEN",
        "WORK_DOCUMENT_ALREADY_DECIDED", "WORK_RETURN_REASON_INVALID", "WORK_DOCUMENT_IMMUTABLE", "WORK_HAS_SUBMISSIONS",
        "WORK_DOCUMENT_NOT_FOUND", "WORK_UPDATE_FORBIDDEN", "WORK_DEPARTMENT_FORBIDDEN", "WORK_DEPARTMENT_DUPLICATE",
        "WORK_NOT_APPROVED", "ADMIN_USE_MANAGEMENT", "MODERATOR_DEPARTMENT_SCOPE", "WORK_ASSIGNEES_REQUIRED",
        "WORK_ASSIGNMENTS_REQUIRED", "INVALID_WORK_ASSIGNEE", "INVALID_WORK_TITLE", "INVALID_WORK_CONTENT",
        "INVALID_WORK_DEADLINE", "INVALID_WORK_FILE", "WORK_FILE_TOO_LARGE", "WORK_EVIDENCE_REQUIRED",
        "WORK_COMPLETION_REVIEWER_REQUIRED", "WORK_COMPLETION_NOT_PENDING", "INVALID_REJECTION_REASON",
    ]

    static func workMessage(_ code: String) -> String? {
        switch code {
        case "WORK_ASSIGNEE_BGH_FORBIDDEN": return "Văn thư không thể giao công việc cho Ban giám hiệu."
        case "WORK_ASSIGNEE_OPS_FORBIDDEN":
            return "Chỉ được giao công việc cho Quản trị viên/Văn thư khác cùng phòng ban."
        case "WORK_ASSIGNEE_NOT_SUBORDINATE":
            return "Chỉ được giao cho người có cấp thấp hơn bạn. Tổ trưởng/tổ phó chỉ giao trong phòng ban của mình."
        case "WORK_APPROVER_REQUIRED":
            return "Công việc do Văn thư/Quản trị tạo cần chọn ít nhất một người duyệt thuộc Ban giám hiệu."
        case "WORK_APPROVERS_REQUIRED": return "Vui lòng chọn ít nhất một người duyệt."
        case "INVALID_WORK_APPROVER":
            return "Người duyệt phải là thành viên Ban giám hiệu (cấp 4 hoặc 5 sao) đang hoạt động, không phải Administrator/Moderator."
        case "WORK_APPROVER_FORBIDDEN": return "Bạn không nằm trong danh sách duyệt công việc này."
        case "WORK_DOCUMENT_ALREADY_DECIDED":
            return "Công việc này đã được duyệt hoặc trả lại, không thể đổi quyết định."
        case "WORK_RETURN_REASON_INVALID": return "Vui lòng nhập lý do trả lại (tối đa 500 ký tự)."
        case "WORK_DOCUMENT_IMMUTABLE":
            return "Công việc đã có người duyệt hoặc người nộp nên không thể sửa hoặc xóa."
        case "WORK_HAS_SUBMISSIONS": return "Đã có người nộp kết quả nên không thể sửa công việc này."
        case "WORK_DOCUMENT_NOT_FOUND": return "Không tìm thấy công việc hoặc công việc đã bị xóa."
        case "WORK_UPDATE_FORBIDDEN": return "Chỉ người tạo mới được sửa hoặc xóa công việc này."
        case "WORK_DEPARTMENT_FORBIDDEN": return "Chỉ Văn thư và Ban giám hiệu được giao việc cho cả phòng ban."
        case "WORK_DEPARTMENT_DUPLICATE": return "Mỗi phòng ban chỉ được nhận một đầu việc trong cùng công văn."
        case "WORK_NOT_APPROVED": return "Công việc chưa được Ban giám hiệu duyệt đủ."
        case "ADMIN_USE_MANAGEMENT":
            return "Administrator/Moderator quản lý công việc, không duyệt thay Ban giám hiệu."
        case "MODERATOR_DEPARTMENT_SCOPE": return "Moderator chỉ được thao tác trong phòng ban được gán."
        case "WORK_ASSIGNEES_REQUIRED": return "Vui lòng chọn người thực hiện."
        case "WORK_ASSIGNMENTS_REQUIRED": return "Vui lòng thêm ít nhất một phân công."
        case "INVALID_WORK_ASSIGNEE": return "Người thực hiện phải cùng phòng ban và có cấp sao thấp hơn bạn."
        case "INVALID_WORK_TITLE": return "Vui lòng nhập tên công việc (tối đa 200 ký tự)."
        case "INVALID_WORK_CONTENT": return "Nội dung công việc bắt buộc và tối đa 2.000 ký tự."
        case "INVALID_WORK_DEADLINE": return "Hạn chót công việc không hợp lệ."
        case "INVALID_WORK_FILE": return "Tệp công văn không đúng định dạng được hỗ trợ."
        case "WORK_FILE_TOO_LARGE": return "Tệp công văn không được vượt quá 20MB."
        case "WORK_EVIDENCE_REQUIRED": return "Khi nộp việc phải đính kèm file bằng chứng hoàn thành."
        case "WORK_COMPLETION_REVIEWER_REQUIRED":
            return "Chỉ người tạo công việc mới được đánh dấu hoàn thành hoặc trả về."
        case "WORK_COMPLETION_NOT_PENDING": return "Task không còn ở trạng thái chờ duyệt hoàn thành."
        case "INVALID_REJECTION_REASON": return "Vui lòng nhập lý do chưa duyệt (tối đa 500 ký tự)."
        default: return nil
        }
    }

    /// Bán trú codes (web `BoardingManagement` errorMessage); before the generic FORBIDDEN/Invalid wording.
    static let boardingCodes = [
        "BOARDING_TEACHERS_REQUIRED", "INVALID_BOARDING_TEACHER", "BOARDING_PERIOD_EXISTS",
        "BOARDING_PERIOD_NOT_FOUND", "BOARDING_PERIOD_FORBIDDEN", "INVALID_SEMESTER", "INVALID_SCHOOL_YEAR",
    ]

    static func boardingMessage(_ code: String) -> String? {
        switch code {
        case "INVALID_SEMESTER": return "Học kỳ chỉ được chọn 1 hoặc 2."
        case "INVALID_SCHOOL_YEAR": return "Năm học không hợp lệ."
        case "BOARDING_TEACHERS_REQUIRED": return "Vui lòng chọn ít nhất một giáo viên."
        case "INVALID_BOARDING_TEACHER": return "Có giáo viên không hợp lệ hoặc đã ngưng hoạt động."
        case "BOARDING_PERIOD_EXISTS": return "Kỳ bán trú này đã tồn tại."
        case "BOARDING_PERIOD_NOT_FOUND": return "Không tìm thấy kỳ bán trú."
        case "BOARDING_PERIOD_FORBIDDEN": return "Bạn không có quyền xem kỳ bán trú này."
        default: return nil
        }
    }

    /// Duty and weekly-approval codes; checked before the generic "Invalid…" login wording.
    static func dutyMessage(_ code: String) -> String? {
        switch code {
        case "DUTY_WEEK_MANAGER_REQUIRED": return "Chỉ văn thư (admin/mod) được nộp lịch tuần."
        case "DUTY_WEEK_REVIEWER_REQUIRED": return "Chỉ Ban Giám hiệu được duyệt hoặc trả lại lịch tuần."
        case "DUTY_WEEK_ALREADY_SUBMITTED": return "Lịch tuần này đang chờ Ban Giám hiệu duyệt."
        case "DUTY_WEEK_NOTHING_TO_SUBMIT": return "Lịch tuần này không có thay đổi nào cần duyệt."
        case "DUTY_WEEK_NOT_SUBMITTED": return "Lịch tuần này không còn ở trạng thái chờ duyệt."
        case "DUTY_WEEK_CHANGED": return "Văn thư vừa sửa lịch tuần này. Hãy xem lại trước khi duyệt."
        case "DUTY_WEEK_RETURN_NOTE_REQUIRED": return "Vui lòng ghi lý do trả lại."
        case "DUTY_WEEK_RETURN_NOTE_TOO_LONG": return "Lý do trả lại tối đa 500 ký tự."
        case "DUTY_UPDATE_FORBIDDEN": return "Bạn không thể sửa công tác này."
        case "DUTY_NOT_FOUND": return "Công tác không còn tồn tại."
        case "INVALID_DUTY_TITLE": return "Tên công tác bắt buộc, tối đa 200 ký tự."
        case "INVALID_CONTENT": return "Nội dung công tác bắt buộc, tối đa 200 ký tự."
        case "INVALID_LOCATION": return "Địa điểm bắt buộc, tối đa 200 ký tự."
        case "INVALID_OTHER_PARTICIPANTS": return "Thành phần khác tối đa 500 ký tự."
        case "INVALID_PARTICIPANT": return "Có người tham gia không còn hoạt động."
        case "INVALID_DEPARTMENT": return "Có phòng ban không còn hoạt động."
        case "END_BEFORE_START": return "Thời gian kết thúc phải sau thời gian bắt đầu."
        default: return nil
        }
    }

    /// Điểm danh, Lớp chủ nhiệm and "Việc của tôi" codes (mirrors src/lib/appErrorMessage.js). Listed before the
    /// generic codes so INVALID_TODO_* / INVALID_DATE never fall into the "Invalid…" login wording.
    static let schoolFeedbackCodes = [
        "ATTENDANCE_CAMERA_IMPORT_RETIRED", "SUPERVISOR_REQUIRED", "ATTENDANCE_DATE_TODAY_ONLY",
        "ATTENDANCE_STUDENT_NOT_IN_CLASS", "ATTENDANCE_TOO_MANY_ABSENT", "ATTENDANCE_DATE_OUTSIDE_YEAR",
        "ATTENDANCE_DATE_IN_FUTURE", "SCHOOL_YEAR_NOT_FOUND", "DISPOSITION_FORBIDDEN", "DISPOSITION_BATCH_TOO_LARGE",
        "INVALID_TODO_TITLE", "INVALID_TODO_NOTE", "INVALID_TODO_TIME", "TODO_REMIND_IN_PAST", "TODO_NOT_FOUND",
        "INVALID_DATE_RANGE", "INVALID_DATE",
    ]

    static func schoolFeedbackMessage(_ code: String) -> String? {
        switch code {
        case "ATTENDANCE_CAMERA_IMPORT_RETIRED": return "Nhập file điểm danh camera đã ngừng sử dụng. Giám thị điểm danh tại menu Điểm danh."
        case "SUPERVISOR_REQUIRED": return "Chỉ Giám thị hoặc Admin/Mod mới được điểm danh."
        case "ATTENDANCE_DATE_TODAY_ONLY": return "Giám thị chỉ được điểm danh cho ngày hôm nay."
        case "ATTENDANCE_STUDENT_NOT_IN_CLASS": return "Có học sinh không thuộc lớp này vào ngày điểm danh. Vui lòng tải lại rồi lưu lại."
        case "ATTENDANCE_TOO_MANY_ABSENT": return "Số học sinh vắng vượt quá giới hạn của một lớp."
        case "ATTENDANCE_DATE_OUTSIDE_YEAR": return "Ngày điểm danh nằm ngoài thời gian của năm học."
        case "ATTENDANCE_DATE_IN_FUTURE": return "Không thể điểm danh cho ngày trong tương lai."
        case "SCHOOL_YEAR_NOT_FOUND": return "Không tìm thấy năm học."
        case "CLASS_NOT_FOUND": return "Không tìm thấy lớp."
        case "CLASS_ARCHIVED": return "Lớp đã lưu trữ. Không thể phân công, nhập danh sách hoặc điểm danh."
        case "DISPOSITION_FORBIDDEN": return "Chỉ GVCN của lớp trong ngày đó hoặc Admin/Mod mới được phân loại vắng."
        case "DISPOSITION_NOT_ABSENT": return "Chỉ đánh dấu được học sinh đang Vắng."
        case "DISPOSITION_BATCH_TOO_LARGE": return "Mỗi lần chỉ phân loại tối đa 100 học sinh."
        case "INVALID_DISPOSITION": return "Phân loại vắng không hợp lệ."
        case "ATTENDANCE_DAY_NOT_FOUND": return "Không tìm thấy buổi điểm danh."
        case "INVALID_TODO_TITLE": return "Vui lòng nhập tên việc (tối đa 200 ký tự)."
        case "INVALID_TODO_NOTE": return "Ghi chú tối đa 2000 ký tự."
        case "INVALID_TODO_TIME": return "Thời gian không hợp lệ."
        case "TODO_REMIND_IN_PAST": return "Giờ nhắc phải ở tương lai."
        case "TODO_NOT_FOUND": return "Việc này không còn tồn tại."
        case "INVALID_DATE": return "Ngày không hợp lệ."
        case "INVALID_DATE_RANGE": return "Ngày bắt đầu phải trước hoặc bằng ngày kết thúc."
        default: return nil
        }
    }

    static func humanize(_ message: String) -> String {
        let code = extractCode(message)
        if let work = workMessage(code) { return work }
        if let boarding = boardingMessage(code) { return boarding }
        if let duty = dutyMessage(code) { return duty }
        if let school = schoolFeedbackMessage(code) { return school }
        switch true {
        case code == "INVALID_PHONE": return "Số điện thoại không hợp lệ (6–20 ký tự)."
        case code == "INVALID_NAME": return "Họ tên phải có 1–120 ký tự."
        case code == "INVALID_TEXT": return "Ghi chú liên hệ tối đa 300 ký tự."
        case code == "INVALID_DISPOSITION_NOTE": return "Ghi chú phân loại tối đa 500 ký tự."
        case code == "CORRECTION_REASON_REQUIRED": return "Cần lý do hoặc ghi chú."
        case code == "GUARDIAN_LIMIT": return "Tối đa 6 người giám hộ đang hoạt động."
        case code == "INVALID_AVATAR_FILE":
            return "Ảnh đại diện phải là PNG, JPG hoặc WEBP."
        case code == "AVATAR_FILE_TOO_LARGE":
            return "Ảnh đại diện không được vượt quá 2MB."
        case code == "AVATAR_UPLOAD_NOT_FOUND":
            return "Không tìm thấy ảnh vừa tải lên. Vui lòng chọn lại."
        case code == "AVATAR_NOT_FOUND":
            return "Chưa có ảnh đại diện."
        case code == "AVATAR_UPLOAD_FAILED":
            return "Không thể cập nhật ảnh đại diện. Vui lòng thử lại."
        case code.localizedCaseInsensitiveContains("Invalid"), code.localizedCaseInsensitiveContains("credentials"):
            return "Email hoặc mật khẩu không đúng."
        case code == "ACCOUNT_LOCKED":
            return "Tài khoản đã bị khóa do đăng nhập sai quá số lần. Liên hệ quản trị viên để mở khóa."
        case code == "USER_NOT_ACTIVE": return "Tài khoản chưa được kích hoạt hoặc đã bị khóa."
        case code == "PASSWORD_TOO_SHORT": return "Mật khẩu phải có ít nhất 8 ký tự."
        case code == "PASSWORD_CHANGE_FAILED": return "Không đổi được mật khẩu. Thử lại sau."
        case code == "PASSWORD_CHANGED_SYNC_PENDING": return "Mật khẩu đã đổi nhưng hồ sơ chưa đồng bộ. Đăng nhập lại."
        case code == "PASSWORD_CHANGE_REQUIRED": return "Bạn cần đổi mật khẩu trước khi tiếp tục."
        case code == "SESSION_TIMEOUT":
            return "Không kết nối được máy chủ. Thử mở lại ứng dụng."
        case code == "PASSWORD_RESET_FAILED": return "Không thể đặt lại mật khẩu. Thử lại sau."
        case code == "PASSWORD_RESET_EMAIL_FAILED":
            return "Đã tạo mật khẩu tạm nhưng chưa gửi được email. Liên hệ quản trị viên."
        case code == "MAIL_NOT_CONFIGURED", code == "MAIL_AUTH_FAILED":
            return "Hệ thống chưa gửi được email. Liên hệ quản trị viên."
        case code == "INVALID_EMAIL": return "Email không hợp lệ."
        case code == "ASSIGNMENT_CREATE_FORBIDDEN":
            return "Bạn không có quyền tạo công tác hoặc công việc."
        case code == "INVALID_WORK_TITLE": return "Vui lòng nhập tên công việc (tối đa 200 ký tự)."
        case code == "INVALID_WORK_CONTENT": return "Nội dung công việc bắt buộc và tối đa 2.000 ký tự."
        case code == "INVALID_WORK_DEADLINE": return "Hạn chót công việc không hợp lệ."
        case code == "INVALID_WORK_ASSIGNEE":
            return "Người thực hiện phải cùng phòng ban và có cấp sao thấp hơn bạn."
        case code == "INVALID_WORK_FILE": return "Tệp công văn không đúng định dạng được hỗ trợ."
        case code == "DOCUMENT_TYPE_REQUIRED": return "Vui lòng chọn loại văn bản cho file đính kèm."
        case code == "INVALID_DOCUMENT_TYPE": return "Loại văn bản không hợp lệ hoặc đã ngưng sử dụng."
        case code == "WORK_ASSIGNMENTS_REQUIRED": return "Vui lòng thêm ít nhất một phân công."
        case code == "WORK_DEPARTMENT_FORBIDDEN":
            return "Tổ trưởng/tổ phó chỉ được giao công việc cho cấp dưới, không chọn cả phòng ban."
        case code == "WORK_DEPARTMENT_DUPLICATE":
            return "Mỗi phòng ban chỉ được nhận một đầu việc trong cùng công văn."
        case code == "NOT_A_SUBORDINATE":
            return "Chỉ được giao hoặc cập nhật cấp dưới trong cùng phòng ban."
        case code == "DUTY_CHAT_EMPTY", code == "WORK_CHAT_EMPTY":
            return "Vui lòng nhập nội dung tin nhắn."
        case code == "DUTY_CHAT_TOO_LONG", code == "WORK_CHAT_TOO_LONG":
            return "Tin nhắn quá dài (tối đa 4000 ký tự)."
        case code == "DUTY_CHAT_RECALL_TOO_LATE", code == "WORK_CHAT_RECALL_TOO_LATE":
            return "Đã quá 15 phút, không thể thu hồi tin nhắn này."
        case code == "DUTY_CHAT_RECALL_FORBIDDEN", code == "WORK_CHAT_RECALL_FORBIDDEN":
            return "Bạn chỉ có thể thu hồi tin nhắn của mình."
        case code == "DUTY_CHAT_FORBIDDEN", code == "WORK_CHAT_FORBIDDEN":
            return "Bạn không có quyền trao đổi mục này."
        case code == "WORK_DOCUMENT_IMMUTABLE":
            return "Đã có người nộp · Không thể sửa hoặc xóa"
        case code == "WORK_UPDATE_FORBIDDEN":
            return "Bạn không có quyền sửa hoặc xóa công việc này."
        case code == "WORK_DOCUMENT_NOT_FOUND":
            return "Công việc không còn tồn tại."
        case code.localizedCaseInsensitiveContains("FORBIDDEN"):
            return "Bạn không có quyền thực hiện thao tác này."
        default: return String(code.prefix(180))
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

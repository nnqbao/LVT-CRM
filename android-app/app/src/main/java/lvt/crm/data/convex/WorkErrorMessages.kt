package lvt.crm.data.convex

/**
 * Công việc error codes → the web's Vietnamese messages (src/lib/appErrorMessage.js).
 * Matched before the generic rules in [ConvexHttpClient.humanize] so codes such as
 * `INVALID_WORK_APPROVER` are never mistaken for a login "Invalid credentials" error.
 */
object WorkErrorMessages {
    val messages: Map<String, String> = linkedMapOf(
        "INVALID_WORK_TITLE" to "Vui lòng nhập tên công việc (tối đa 200 ký tự).",
        "INVALID_WORK_FILE" to "Tệp công văn không đúng định dạng được hỗ trợ.",
        "WORK_FILE_TOO_LARGE" to "Tệp công văn không được vượt quá 20MB.",
        "INVALID_WORK_DEADLINE" to "Hạn chót công việc không hợp lệ.",
        "INVALID_WORK_CONTENT" to "Nội dung công việc bắt buộc và tối đa 2.000 ký tự.",
        "WORK_ASSIGNMENTS_REQUIRED" to "Vui lòng thêm ít nhất một phân công.",
        "WORK_DEPARTMENTS_REQUIRED" to "Vui lòng thêm ít nhất một phòng ban nhận việc.",
        "WORK_DEPARTMENT_DUPLICATE" to "Mỗi phòng ban chỉ được nhận một đầu việc trong cùng công văn.",
        "WORK_APPROVERS_REQUIRED" to "Vui lòng chọn ít nhất một người duyệt.",
        "INVALID_WORK_APPROVER" to
            "Người duyệt phải là thành viên Ban giám hiệu (cấp 4 hoặc 5 sao) đang hoạt động, không phải Administrator/Moderator.",
        "WORK_APPROVER_REQUIRED" to
            "Công việc do Văn thư/Quản trị tạo cần chọn ít nhất một người duyệt thuộc Ban giám hiệu.",
        "WORK_APPROVER_FORBIDDEN" to "Bạn không nằm trong danh sách duyệt công việc này.",
        "WORK_DOCUMENT_ALREADY_DECIDED" to "Công việc này đã được duyệt hoặc trả lại, không thể đổi quyết định.",
        "WORK_RETURN_REASON_INVALID" to "Vui lòng nhập lý do trả lại (tối đa 500 ký tự).",
        "WORK_DOCUMENT_IMMUTABLE" to "Công việc đã có người duyệt hoặc người nộp nên không thể sửa hoặc xóa.",
        "WORK_DOCUMENT_NOT_FOUND" to "Không tìm thấy công việc hoặc công việc đã bị xóa.",
        "WORK_HAS_SUBMISSIONS" to "Đã có người nộp kết quả nên không thể sửa công việc này.",
        "WORK_UPDATE_FORBIDDEN" to "Chỉ người tạo mới được sửa hoặc xóa công việc này.",
        "WORK_ASSIGNEE_BGH_FORBIDDEN" to "Văn thư không thể giao công việc cho Ban giám hiệu.",
        // Sandbox addition in progress (no web copy yet): văn thư/admin may assign another
        // văn thư/admin only inside the same department.
        "WORK_ASSIGNEE_OPS_FORBIDDEN" to
            "Chỉ giao việc cho tài khoản quản trị cùng phòng ban.",
        "WORK_DEPARTMENT_FORBIDDEN" to "Chỉ Văn thư và Ban giám hiệu được giao việc cho cả phòng ban.",
        "WORK_ASSIGNEE_NOT_SUBORDINATE" to
            "Chỉ được giao cho người có cấp thấp hơn bạn. Tổ trưởng/tổ phó chỉ giao trong phòng ban của mình.",
        "ADMIN_USE_MANAGEMENT" to "Administrator/Moderator quản lý công việc, không duyệt thay Ban giám hiệu.",
        "WORK_NOT_APPROVED" to "Công việc chưa được Ban giám hiệu duyệt đủ.",
        "MODERATOR_DEPARTMENT_SCOPE" to "Moderator chỉ được thao tác trong phòng ban được gán.",
        "INVALID_WORK_ASSIGNEE" to "Người thực hiện phải cùng phòng ban và có cấp sao thấp hơn bạn.",
        "WORK_ASSIGNEES_REQUIRED" to "Vui lòng chọn người thực hiện.",
        "WORK_EXECUTOR_REQUIRED" to "Chỉ người được giao mới được hoàn thành task.",
        "INVALID_QUALITY_PERCENT" to "Mức độ hoàn thành phải từ 0 đến 100%.",
        "INVALID_REJECTION_REASON" to "Vui lòng nhập lý do chưa duyệt (tối đa 500 ký tự).",
        "DOCUMENT_TYPE_REQUIRED" to "Vui lòng chọn loại văn bản cho file đính kèm.",
        "INVALID_DOCUMENT_TYPE" to "Loại văn bản không hợp lệ hoặc đã ngưng sử dụng.",
        "ASSIGNMENT_CREATE_FORBIDDEN" to "Bạn không có quyền tạo công tác hoặc công việc.",
    )

    /** Longest code first so a code that contains another (e.g. `INVALID_WORK_APPROVER`) wins. */
    private val codesByLength = messages.keys.sortedByDescending { it.length }

    fun codeIn(raw: String): String? = codesByLength.firstOrNull { raw.contains(it) }

    fun messageFor(raw: String): String? = codeIn(raw)?.let(messages::get)
}

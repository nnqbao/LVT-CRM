package lvt.crm.data.convex

/**
 * Lớp học (Sổ đầu bài, Học bạ) and quick sign-in (vân tay, passkey) error codes → Vietnamese
 * (docs/native-teaching-auth-contract.md §4). Matched before the generic rules in
 * [ConvexHttpClient.humanize] so codes such as `DEVICE_CREDENTIAL_INVALID` or `INVALID_SCORE` are
 * never mistaken for a login "Invalid credentials" error.
 */
object TeachingAuthErrorMessages {
    const val DEVICE_CREDENTIAL_INVALID = "DEVICE_CREDENTIAL_INVALID"

    val messages: Map<String, String> = linkedMapOf(
        "CHALLENGE_INVALID" to "Phiên xác thực đã hết hạn. Vui lòng thử lại.",
        DEVICE_CREDENTIAL_INVALID to
            "Vân tay / Face ID hoặc passkey trên máy này không còn hiệu lực. Đăng nhập bằng mật khẩu rồi bật lại.",
        "DEVICE_SIGNATURE_INVALID" to "Không xác thực được thiết bị.",
        "PASSKEY_VERIFICATION_FAILED" to "Không xác thực được passkey.",
        "DEVICE_CREDENTIAL_LIMIT" to "Tài khoản đã có tối đa 10 thiết bị đăng nhập nhanh.",
        "DEVICE_CREDENTIAL_NOT_FOUND" to "Thiết bị đăng nhập nhanh không còn tồn tại.",
        "INVALID_PUBLIC_KEY" to "Không xác thực được thiết bị.",
        "LESSON_NOT_SCHEDULED" to "Bạn không có tiết này ở lớp vào ngày đã chọn.",
        "LESSON_IN_FUTURE" to "Chưa thể ghi Sổ đầu bài cho tiết chưa diễn ra.",
        "INVALID_RATING" to "Chọn từ 1 đến 5 sao.",
        "INVALID_LESSON_COMMENT" to "Nhận xét tối đa 1.000 ký tự.",
        "INVALID_SCORE" to "Điểm từ 0 đến 10, tối đa 2 chữ số thập phân.",
        "INVALID_SEMESTER" to "Học kỳ không hợp lệ.",
        "GRADE_SUBJECT_FORBIDDEN" to "Bạn chỉ nhập điểm môn mình dạy ở lớp này.",
        "GRADEBOOK_FORBIDDEN" to "Bạn không phụ trách lớp của học sinh này.",
        "GRADE_NOT_FOUND" to "Điểm này không còn tồn tại.",
        "SCHOOL_YEAR_LOCKED" to "Năm học đã khóa.",
        "TEST_TYPE_NOT_FOUND" to "Loại kiểm tra không còn.",
        "SUBJECT_NOT_FOUND" to "Môn học không còn.",
        "REPORT_RANGE_TOO_LONG" to "Khoảng ngày quá dài.",
        "TEACHER_SCHEDULE_FORBIDDEN" to "Bạn chỉ xem được lịch dạy của mình.",
    )

    /** Longest code first so a code that contains another wins. */
    private val codesByLength = messages.keys.sortedByDescending { it.length }

    fun codeIn(raw: String): String? = codesByLength.firstOrNull { raw.contains(it) }

    fun messageFor(raw: String): String? = codeIn(raw)?.let(messages::get)
}

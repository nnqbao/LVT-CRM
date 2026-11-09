package lvt.crm.data.convex

import org.junit.Assert.assertEquals
import org.junit.Test

class TeachingAuthErrorMessagesTest {
    private fun server(code: String) =
        "[CONVEX M(gradebook:addEntry)] [Request ID: abc] Server Error\nUncaught Error: $code\n    at handler (../convex/gradebook.ts:300:11)"

    @Test
    fun contractCodesUseVietnameseMessages() {
        assertEquals("Phiên xác thực đã hết hạn. Vui lòng thử lại.", ConvexHttpClient.humanize(server("CHALLENGE_INVALID")))
        assertEquals(
            "Vân tay / Face ID hoặc passkey trên máy này không còn hiệu lực. Đăng nhập bằng mật khẩu rồi bật lại.",
            ConvexHttpClient.humanize(server("DEVICE_CREDENTIAL_INVALID")),
        )
        assertEquals("Không xác thực được thiết bị.", ConvexHttpClient.humanize(server("DEVICE_SIGNATURE_INVALID")))
        assertEquals("Không xác thực được passkey.", ConvexHttpClient.humanize(server("PASSKEY_VERIFICATION_FAILED")))
        assertEquals("Tài khoản đã có tối đa 10 thiết bị đăng nhập nhanh.", ConvexHttpClient.humanize(server("DEVICE_CREDENTIAL_LIMIT")))
        assertEquals("Bạn không có tiết này ở lớp vào ngày đã chọn.", ConvexHttpClient.humanize(server("LESSON_NOT_SCHEDULED")))
        assertEquals("Chưa thể ghi Sổ đầu bài cho tiết chưa diễn ra.", ConvexHttpClient.humanize(server("LESSON_IN_FUTURE")))
        assertEquals("Chọn từ 1 đến 5 sao.", ConvexHttpClient.humanize(server("INVALID_RATING")))
        assertEquals("Điểm từ 0 đến 10, tối đa 2 chữ số thập phân.", ConvexHttpClient.humanize(server("INVALID_SCORE")))
        assertEquals("Bạn chỉ nhập điểm môn mình dạy ở lớp này.", ConvexHttpClient.humanize(server("GRADE_SUBJECT_FORBIDDEN")))
        assertEquals("Bạn không phụ trách lớp của học sinh này.", ConvexHttpClient.humanize(server("GRADEBOOK_FORBIDDEN")))
        assertEquals("Năm học đã khóa.", ConvexHttpClient.humanize(server("SCHOOL_YEAR_LOCKED")))
        assertEquals("Loại kiểm tra không còn.", ConvexHttpClient.humanize(server("TEST_TYPE_NOT_FOUND")))
        assertEquals("Môn học không còn.", ConvexHttpClient.humanize(server("SUBJECT_NOT_FOUND")))
    }

    @Test
    fun codesAreExtractedBeforeGenericRules() {
        assertEquals("DEVICE_CREDENTIAL_INVALID", ConvexHttpClient.extractCode(server("DEVICE_CREDENTIAL_INVALID")))
        assertEquals("GRADE_SUBJECT_FORBIDDEN", ConvexHttpClient.extractCode(server("GRADE_SUBJECT_FORBIDDEN")))
        // Attendance codes that contain shorter words keep their own meaning.
        assertEquals("ATTENDANCE_STUDENT_NOT_IN_CLASS", ConvexHttpClient.extractCode(server("ATTENDANCE_STUDENT_NOT_IN_CLASS")))
    }
}

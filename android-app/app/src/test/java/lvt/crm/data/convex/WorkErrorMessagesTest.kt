package lvt.crm.data.convex

import org.junit.Assert.assertEquals
import org.junit.Test

class WorkErrorMessagesTest {
    private fun server(code: String) =
        "[CONVEX M(work:createDocument)] [Request ID: abc] Server Error\nUncaught Error: $code\n    at handler (../convex/work.ts:1200:11)"

    @Test
    fun newApprovalCodesUseTheWebMessages() {
        assertEquals(
            "Công việc do Văn thư/Quản trị tạo cần chọn ít nhất một người duyệt thuộc Ban giám hiệu.",
            ConvexHttpClient.humanize(server("WORK_APPROVER_REQUIRED")),
        )
        assertEquals(
            "Vui lòng nhập lý do trả lại (tối đa 500 ký tự).",
            ConvexHttpClient.humanize(server("WORK_RETURN_REASON_INVALID")),
        )
        assertEquals(
            "Văn thư không thể giao công việc cho Ban giám hiệu.",
            ConvexHttpClient.humanize(server("WORK_ASSIGNEE_BGH_FORBIDDEN")),
        )
        assertEquals(
            "Chỉ được giao việc cho Văn thư/Quản trị viên khác trong cùng phòng ban.",
            ConvexHttpClient.humanize(server("WORK_ASSIGNEE_OPS_FORBIDDEN")),
        )
        assertEquals(
            "Moderator chỉ được thao tác trong phòng ban được gán.",
            ConvexHttpClient.humanize(server("MODERATOR_DEPARTMENT_SCOPE")),
        )
        assertEquals(
            "Công việc này đã được duyệt hoặc trả lại, không thể đổi quyết định.",
            ConvexHttpClient.humanize(server("WORK_DOCUMENT_ALREADY_DECIDED")),
        )
        assertEquals(
            "Chỉ Văn thư và Ban giám hiệu được giao việc cho cả phòng ban.",
            ConvexHttpClient.humanize(server("WORK_DEPARTMENT_FORBIDDEN")),
        )
        assertEquals(
            "Administrator/Moderator quản lý công việc, không duyệt thay Ban giám hiệu.",
            ConvexHttpClient.humanize(server("ADMIN_USE_MANAGEMENT")),
        )
    }

    @Test
    fun invalidWorkCodesAreNotMistakenForLoginErrors() {
        assertEquals(
            "Người duyệt phải là thành viên Ban giám hiệu (cấp 4 hoặc 5 sao) đang hoạt động, không phải Administrator/Moderator.",
            ConvexHttpClient.humanize(server("INVALID_WORK_APPROVER")),
        )
        assertEquals("Hạn chót công việc không hợp lệ.", ConvexHttpClient.humanize(server("INVALID_WORK_DEADLINE")))
        assertEquals("INVALID_WORK_APPROVER", ConvexHttpClient.extractCode(server("INVALID_WORK_APPROVER")))
        assertEquals("WORK_APPROVER_FORBIDDEN", ConvexHttpClient.extractCode(server("WORK_APPROVER_FORBIDDEN")))
    }

    @Test
    fun loginAndOtherErrorsAreUnchanged() {
        assertEquals("Email hoặc mật khẩu không đúng.", ConvexHttpClient.humanize("InvalidSecret"))
        assertEquals("Đã quá 15 phút, không thể thu hồi tin nhắn này.", ConvexHttpClient.humanize("WORK_CHAT_RECALL_TOO_LATE"))
    }
}

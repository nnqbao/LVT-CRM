package lvt.crm.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationPresentationTest {
    @Test
    fun workApprovalKindsOpenTheWorkScreenFocusedOnTheDocument() {
        listOf("approval", "work_approved", "work_returned").forEach { sourceType ->
            val destination = NotificationDestination("work", sourceType, "doc-1", "work:$sourceType:doc-1:1")
            assertEquals("work", destination.route)
            assertFalse(destination.opensChat)
            assertFalse(destination.opensTodos)
            assertEquals("doc-1", destination.sourceId)
        }
    }

    @Test
    fun labelsMatchTheBackendKinds() {
        assertEquals("Công việc chờ duyệt", NotificationPresentation.kindLabel("work", "approval"))
        assertEquals("Công việc đã duyệt", NotificationPresentation.kindLabel("work", "work_approved"))
        assertEquals("Công việc bị trả lại", NotificationPresentation.kindLabel("work", "work_returned"))
        assertEquals("Công việc", NotificationPresentation.kindLabel("work", "department_work"))
        assertEquals("Trao đổi", NotificationPresentation.kindLabel("work", "work_chat"))
        assertEquals("Việc của tôi", NotificationPresentation.kindLabel("todo", "todo_reminder"))
    }

    @Test
    fun systemTitlesForPush() {
        assertEquals("Công việc chờ duyệt", NotificationPresentation.systemTitle("work", "approval", "Cần duyệt"))
        assertEquals("Công việc bị trả lại", NotificationPresentation.systemTitle("work", "work_returned", "Bị trả lại"))
        assertEquals("Công việc đã được duyệt", NotificationPresentation.systemTitle("work", "work_approved", "Đã duyệt"))
        assertEquals("Hoàn thành bị từ chối", NotificationPresentation.systemTitle("work", "completion_rejected", ""))
        assertEquals("Công việc · 24h", NotificationPresentation.systemTitle("work", "department_work", "24h"))
        assertEquals("Công tác · 1h", NotificationPresentation.systemTitle("duty", "duty", "1h"))
    }

    @Test
    fun rejectionAccentAndEventTime() {
        assertTrue(NotificationPresentation.isRejection("work_returned"))
        assertTrue(NotificationPresentation.isRejection("completion_rejected"))
        assertFalse(NotificationPresentation.isRejection("approval"))
        assertTrue(NotificationPresentation.showsEventTime("work_returned"))
        assertTrue(NotificationPresentation.showsEventTime("work_approved"))
        assertFalse(NotificationPresentation.showsEventTime("approval"))
    }

    @Test
    fun headlineSplitsTheMarkerFromTheWorkTitle() {
        assertEquals(
            "Công việc chờ duyệt:" to "Kế hoạch tháng 11",
            NotificationPresentation.headline("Công việc chờ duyệt: Kế hoạch tháng 11", "work", "approval"),
        )
        assertEquals(
            "Công việc bị trả lại:" to "Báo cáo",
            NotificationPresentation.headline("Công việc bị trả lại: Báo cáo", "work", "work_returned"),
        )
        val plain = NotificationPresentation.headline("Họp tổ", "work", "department_work")
        assertEquals("Họp tổ", plain.first)
        assertNull(plain.second)
        assertEquals("Công việc chờ duyệt", NotificationPresentation.headline("", "work", "approval").first)
    }
}

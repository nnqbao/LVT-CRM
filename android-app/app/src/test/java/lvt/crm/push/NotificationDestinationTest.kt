package lvt.crm.push

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationDestinationTest {
    @Test
    fun dutyNotificationRoutesToDuties() {
        assertEquals("duties", NotificationDestination.routeForKind("duty"))
    }

    @Test
    fun everyNonDutyNotificationRoutesToWork() {
        assertEquals("work", NotificationDestination.routeForKind("work"))
        assertEquals("work", NotificationDestination.routeForKind("approval"))
        assertEquals("work", NotificationDestination.routeForKind(""))
    }

    @Test
    fun chatNotificationsOpenTheHubThread() {
        val duty = NotificationDestination("duty", "duty_chat", "duty-1", "key")
        assertEquals("chat", duty.route)
        assertEquals("duty", duty.chatKind)
        assertTrue(duty.opensChat)
        val work = NotificationDestination("work", "work_chat", "doc-1", "key")
        assertEquals("chat", work.route)
        assertEquals("work", work.chatKind)
        assertTrue(work.opensChat)
        val group = NotificationDestination("group", "group_chat", "group-1", "key")
        assertEquals("chat", group.route)
        assertEquals("group", group.chatKind)
        assertTrue(group.opensChat)
        assertFalse(NotificationDestination("duty", "duty_assigned", "duty-1", null).opensChat)
        assertFalse(NotificationDestination.opensChat("personal_task"))
    }

    @Test
    fun peopleNotificationsOpenTheirWebPage() {
        val fault = NotificationDestination("people", "staff_fault", "fault-1", "people:staff_fault:fault-1", menu = "staff-faults")
        assertTrue(fault.opensWeb)
        assertFalse(fault.opensChat)
        assertEquals("/ghi-nhan-loi", fault.webPath)
        // A person without Ghi nhận lỗi sees the fault in Hồ sơ của tôi (feed menu people-review).
        assertEquals("/danh-gia-nhan-su", NotificationDestination("people", "staff_fault", "fault-1", null, menu = "people-review").webPath)
        assertEquals("/ghi-nhan-loi", NotificationDestination.peopleWebPath("", "staff_fault"))
        listOf("evaluation_text_review", "evaluation_text_approved", "evaluation_text_returned").forEach { sourceType ->
            val comment = NotificationDestination("people", sourceType, "text-1", "key")
            assertTrue(comment.opensWeb)
            assertEquals("/danh-gia-nhan-su", comment.webPath)
        }
        assertEquals("/danh-gia-nhan-su", NotificationDestination.peopleWebPath("work", "evaluation_text_review"))
        assertFalse(NotificationDestination("work", "approval", "doc-1", null).opensWeb)
    }

    @Test
    fun todoRemindersOpenTheWorkHubTodoList() {
        val push = NotificationDestination("todo", "todo_reminder", "todo-1", "todo:todo_reminder:todo-1:1")
        assertEquals("work", push.route)
        assertTrue(push.opensTodos)
        assertFalse(push.opensChat)
        assertTrue(NotificationDestination("", "todo_reminder", "todo-1", null).opensTodos)
        assertFalse(NotificationDestination("work", "approval", "doc-1", null).opensTodos)
        assertFalse(NotificationDestination("duty", "duty_assigned", "duty-1", null).opensTodos)
    }
}

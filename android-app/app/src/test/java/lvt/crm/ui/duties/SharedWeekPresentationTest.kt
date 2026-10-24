package lvt.crm.ui.duties

import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.duties.DutyWeekState
import lvt.crm.data.duties.SharedDutyEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SharedWeekPresentationTest {
    private fun event(
        id: String = "d1",
        startDate: String = "2026-10-20",
        endDate: String = startDate,
        startTime: String = "14:00",
        allDay: Boolean = false,
        other: String = "",
    ) = SharedDutyEvent(
        id = id, title = "Họp tổ Toán", content = "Họp tổ Toán", startDate = startDate, endDate = endDate,
        startTime = startTime, endTime = "16:00", allDay = allDay, locationText = "Phòng họp 1",
        departmentIds = emptyList(), participantUserIds = emptyList(), departmentNames = listOf("Tổ Toán"),
        participantNames = emptyList(), otherParticipants = other, canManage = true, approvalChange = null,
    )

    private fun week(status: String, changeCount: Int = 1, approved: Boolean = false) = DutyWeekState(
        weekStart = "2026-10-19", status = status, changeCount = changeCount, changes = emptyList(),
        missingParticipants = 0, hasApprovedVersion = approved, submittedAt = 1.79e12, submittedByName = "Cô Hoa",
        returnedAt = null, returnedByName = "", returnNote = "", approvedAt = null, approvedByName = "",
    )

    @Test
    fun weekRunsMondayToSaturday() {
        assertEquals("2026-10-19", SharedWeekPresentation.weekStart("2026-10-25"))
        assertEquals("2026-10-19", SharedWeekPresentation.weekStart("2026-10-19"))
        assertEquals("2026-10-24", SharedWeekPresentation.weekEnd("2026-10-19"))
        assertEquals("2026-10-26", SharedWeekPresentation.shiftWeek("2026-10-19", 1))
        assertEquals("Tuần 19/10 – 24/10", SharedWeekPresentation.weekLabel("2026-10-19"))
        assertEquals("Thứ Ba 20/10", SharedWeekPresentation.dayTitle("2026-10-20"))
    }

    @Test
    fun daysGroupEventsAndCarryEarlierStartsToMonday() {
        val days = SharedWeekPresentation.days(
            "2026-10-19",
            listOf(event("a"), event("b", startDate = "2026-10-16", endDate = "2026-10-20", allDay = true)),
        )
        assertEquals(6, days.size)
        assertEquals(listOf("b"), days[0].events.map { it.id })
        assertEquals(listOf("a"), days[1].events.map { it.id })
        assertTrue(days[5].events.isEmpty())
    }

    @Test
    fun timesReadLikeThePaperSheet() {
        assertEquals("14g00", SharedWeekPresentation.timeLabel(event()))
        assertEquals("7g30", SharedWeekPresentation.clock("07:30"))
        assertEquals("Cả ngày", SharedWeekPresentation.timeLabel(event(allDay = true)))
        assertEquals("Đến 22/10", SharedWeekPresentation.timeLabel(event(endDate = "2026-10-22")))
        assertEquals("lúc 10:20, 10/10", SharedWeekPresentation.moment(1_791_602_400_000.0))
    }

    @Test
    fun participantsJoinWithoutDuplicates() {
        assertEquals("Tổ Toán, Khách mời", SharedWeekPresentation.participants(event(other = "Khách mời")))
        assertFalse(SharedWeekPresentation.hasParticipants(event()))
        assertTrue(SharedWeekPresentation.hasParticipants(event(other = "BGH")))
    }

    @Test
    fun actionsFollowRoleAndStatus() {
        assertTrue(SharedWeekPresentation.canSubmit(week("draft"), canSubmit = true))
        assertFalse(SharedWeekPresentation.canSubmit(week("draft"), canSubmit = false))
        assertFalse(SharedWeekPresentation.canSubmit(week("submitted"), canSubmit = true))
        assertFalse(SharedWeekPresentation.canSubmit(week("approved", changeCount = 0), canSubmit = true))
        assertTrue(SharedWeekPresentation.canDecide(week("submitted"), canReview = true))
        assertFalse(SharedWeekPresentation.canDecide(week("returned"), canReview = true))
        assertEquals("Nộp lại cho BGH", SharedWeekPresentation.submitLabel(week("returned")))
        assertEquals("Nộp duyệt lại", SharedWeekPresentation.submitLabel(week("approved_changed", approved = true)))
        assertEquals("Nộp BGH duyệt", SharedWeekPresentation.submitLabel(week("draft")))
    }

    @Test
    fun teachersSeeANoticeForAnEmptyWeek() {
        assertTrue(SharedWeekPresentation.showUnapprovedNotice("public", 0))
        assertFalse(SharedWeekPresentation.showUnapprovedNotice("manager", 0))
        assertFalse(SharedWeekPresentation.showUnapprovedNotice("public", 2))
        assertEquals("Đã duyệt · có thay đổi chờ duyệt", SharedWeekPresentation.pill("approved_changed"))
        assertTrue(SharedWeekPresentation.isWeekNotification("duty_week_review"))
        assertFalse(SharedWeekPresentation.isWeekNotification("duty_assigned"))
    }

    @Test
    fun editRulesMirrorTheServer() {
        val draft = DutyEditRules.draftFrom(event())
        assertNull(DutyEditRules.error(draft))
        assertEquals("Địa điểm bắt buộc, tối đa 200 ký tự.", DutyEditRules.error(draft.copy(locationText = " ")))
        assertEquals(
            "Thời gian kết thúc phải sau thời gian bắt đầu.",
            DutyEditRules.error(draft.copy(endTime = "13:00")),
        )
        val allDay = DutyEditRules.trimmed(draft.copy(allDay = true, endDate = "2026-10-23"))
        assertEquals("2026-10-20", allDay.endDate)
        assertEquals("08:00", allDay.startTime)
        assertEquals("17:00", allDay.endTime)
    }

    @Test
    fun dutyErrorsAreNotMistakenForLoginErrors() {
        assertEquals("Nội dung công tác bắt buộc, tối đa 200 ký tự.", ConvexHttpClient.humanize("Uncaught Error: INVALID_CONTENT"))
        assertEquals("Địa điểm bắt buộc, tối đa 200 ký tự.", ConvexHttpClient.humanize("INVALID_LOCATION"))
        assertEquals(
            "Văn thư vừa sửa lịch tuần này. Hãy xem lại trước khi duyệt.",
            ConvexHttpClient.humanize("Uncaught Error: DUTY_WEEK_CHANGED"),
        )
    }
}

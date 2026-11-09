package lvt.crm.data.teaching

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors src/lib/teachingSchedule.js / convex/teachingPolicy.ts (tests/teaching-policy.test.mjs). */
class TeachingScheduleTest {
    private val year = YearWindow("2026-09-05", "2027-05-31")

    private fun slot(
        weekday: Int,
        session: String = "morning",
        period: Int = 1,
        classId: String = "c1",
        from: String = "2026-09-05",
        to: String? = null,
        subjectId: String = "toan",
    ) = TimetableSlot("s-$weekday-$session-$period-$classId", classId, weekday, session, period, "t1", subjectId, from, to)

    @Test
    fun isoWeekdayIsMondayOne() {
        assertEquals(1, TeachingSchedule.isoWeekday("2026-10-19")) // Thứ 2
        assertEquals(5, TeachingSchedule.isoWeekday("2026-10-23")) // Thứ 6
        assertEquals(7, TeachingSchedule.isoWeekday("2026-10-25")) // Chủ nhật
        assertEquals("Thứ 2", TeachingSchedule.weekdayLabel(1))
        assertEquals("Thứ 6", TeachingSchedule.weekdayLabel(5))
    }

    @Test
    fun slotCoverageIsInclusiveOnBothEnds() {
        val bounded = slot(weekday = 3, from = "2026-10-07", to = "2026-10-21")
        assertFalse(TeachingSchedule.slotCoversDate(bounded, "2026-10-06"))
        assertTrue(TeachingSchedule.slotCoversDate(bounded, "2026-10-07"))
        assertTrue(TeachingSchedule.slotCoversDate(bounded, "2026-10-21"))
        assertFalse(TeachingSchedule.slotCoversDate(bounded, "2026-10-22"))
        val open = slot(weekday = 3, from = "2026-10-07", to = null)
        assertTrue(TeachingSchedule.slotCoversDate(open, "2027-05-26"))
    }

    @Test
    fun expansionSkipsWeekendsHolidaysOutsideYearAndOtherWeekdays() {
        val slots = listOf(
            slot(weekday = 3, period = 2), // Thứ 4
            slot(weekday = 3, session = "afternoon", period = 1, classId = "c2"),
            slot(weekday = 5, period = 3, from = "2026-10-30"), // starts later
        )
        val lessons = TeachingSchedule.expandLessons(slots, "2026-10-19", "2026-10-25", year, setOf("2026-10-21"))
        assertTrue("holiday Thứ 4 21/10 has no lesson", lessons.isEmpty())

        val week = TeachingSchedule.expandLessons(slots, "2026-10-26", "2026-11-01", year, emptySet())
        assertEquals(listOf("2026-10-28", "2026-10-28", "2026-10-30"), week.map { it.date })
        assertEquals(listOf("morning-2", "afternoon-1", "morning-3"), week.map { it.cellKey })

        val beforeYear = TeachingSchedule.expandLessons(slots, "2026-08-01", "2026-09-04", year, emptySet())
        assertTrue(beforeYear.isEmpty())
        val clamped = TeachingSchedule.expandLessons(listOf(slot(weekday = 1)), "2027-05-24", "2027-06-30", year, emptySet())
        assertEquals(listOf("2027-05-24", "2027-05-31"), clamped.map { it.date })
    }

    @Test
    fun replacedSlotHandsOverOnItsEffectiveDate() {
        val old = slot(weekday = 1, from = "2026-09-05", to = "2026-10-18", subjectId = "van")
        val new = slot(weekday = 1, from = "2026-10-19", subjectId = "toan")
        val lessons = TeachingSchedule.expandLessons(listOf(old, new), "2026-10-12", "2026-10-19", year, emptySet())
        assertEquals(listOf("2026-10-12" to "van", "2026-10-19" to "toan"), lessons.map { it.date to it.subjectId })
    }

    @Test
    fun periodTimesAndLabels() {
        assertEquals("07:00", TeachingSchedule.lessonStartTime("morning", 1))
        assertEquals("08:50", TeachingSchedule.lessonStartTime("morning", 3))
        assertEquals("13:30", TeachingSchedule.lessonStartTime("afternoon", 1))
        assertEquals("17:00", TeachingSchedule.lessonStartTime("afternoon", 5))
        val lesson = Lesson("2026-10-21", 3, "morning", 3, "c1", "t1", "toan")
        assertEquals("09:35", TeachingSchedule.lessonEndTime(lesson))
        assertEquals("Tiết 3 sáng", TeachingSchedule.periodLabel("morning", 3))
        assertEquals("Tiết 1 chiều", TeachingSchedule.periodLabel("afternoon", 1))
    }

    @Test
    fun nextLessonKeepsTheLessonInProgressThenLooksAhead() {
        val slots = listOf(
            slot(weekday = 3, period = 1, classId = "a"), // Thứ 4 07:00–07:45
            slot(weekday = 3, period = 3, classId = "b"), // Thứ 4 08:50–09:35
            slot(weekday = 5, period = 2, classId = "a"), // Thứ 6
        )
        val lessons = TeachingSchedule.expandLessons(slots, "2026-10-21", TeachingSchedule.addDays("2026-10-21", 35), year, emptySet())
        val during = TeachingSchedule.nextLessonByClass(lessons, VietnamNow("2026-10-21", "07:30"))
        assertEquals("2026-10-21", during.getValue("a").date)
        val after = TeachingSchedule.nextLessonByClass(lessons, VietnamNow("2026-10-21", "07:46"))
        assertEquals("2026-10-23", after.getValue("a").date)
        assertEquals("2026-10-21", after.getValue("b").date)
        val evening = TeachingSchedule.nextLessonByClass(lessons, VietnamNow("2026-10-21", "18:00"))
        assertEquals("2026-10-28", evening.getValue("b").date)
    }

    @Test
    fun defaultLessonIsTheOneJustTaught() {
        val lessons = TeachingSchedule.expandLessons(
            listOf(slot(weekday = 3, period = 1), slot(weekday = 3, period = 4)),
            "2026-10-21",
            "2026-10-21",
            year,
            emptySet(),
        )
        assertEquals("morning-1", TeachingSchedule.defaultLesson(lessons, "2026-10-21", VietnamNow("2026-10-21", "08:00"))?.cellKey)
        assertEquals("morning-4", TeachingSchedule.defaultLesson(lessons, "2026-10-21", VietnamNow("2026-10-21", "10:00"))?.cellKey)
        assertEquals("morning-1", TeachingSchedule.defaultLesson(lessons, "2026-10-21", VietnamNow("2026-10-21", "06:30"))?.cellKey)
        assertEquals("morning-4", TeachingSchedule.defaultLesson(lessons, "2026-10-21", VietnamNow("2026-10-22", "06:30"))?.cellKey)
        assertNull(TeachingSchedule.defaultLesson(emptyList(), "2026-10-21", VietnamNow("2026-10-21", "08:00")))
    }

    @Test
    fun calendarHelpers() {
        assertEquals("2026-10-19", TeachingSchedule.weekStart("2026-10-25"))
        assertEquals("2026-10-19", TeachingSchedule.weekStart("2026-10-19"))
        assertEquals("2026-02-28", TeachingSchedule.monthEnd("2026-02-10"))
        assertEquals("2027-01-01", TeachingSchedule.addMonths("2026-12-15", 1))
        assertEquals("Thứ 4, 21/10/2026", TeachingSchedule.dayTitle("2026-10-21"))
        assertEquals("Tháng 10/2026", TeachingSchedule.monthLabel("2026-10-21"))
    }

    @Test
    fun semesterDefaultsFromSemester2StartDate() {
        assertEquals(1, TeachingSchedule.semesterForDate("2027-01-10", "2027-01-11"))
        assertEquals(2, TeachingSchedule.semesterForDate("2027-01-11", "2027-01-11"))
        assertEquals(1, TeachingSchedule.semesterForDate("2027-04-01", ""))
        assertEquals(1, TeachingSchedule.semesterForDate("2027-04-01", null))
    }

    @Test
    fun vietnamNowIsUtcPlusSeven() {
        val now = TeachingSchedule.vietnamNow(Instant.parse("2026-10-23T17:30:00Z"))
        assertEquals(VietnamNow("2026-10-24", "00:30"), now)
    }

    @Test
    fun naturalClassOrder() {
        val sorted = listOf("6A10", "6A2", "6A1", "7A1").sortedWith(TeachingSchedule.naturalOrder)
        assertEquals(listOf("6A1", "6A2", "6A10", "7A1"), sorted)
    }
}

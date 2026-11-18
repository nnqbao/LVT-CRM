package lvt.crm.data.teaching

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** One timetable cell of a teacher in a class, valid from [effectiveFrom] to [effectiveTo] (inclusive). */
data class TimetableSlot(
    val id: String,
    val classId: String,
    /** 1 = Thứ 2 … 5 = Thứ 6. */
    val weekday: Int,
    /** `morning` | `afternoon`. */
    val session: String,
    /** 1..5. */
    val period: Int,
    val teacherId: String,
    val subjectId: String,
    val effectiveFrom: String,
    val effectiveTo: String? = null,
)

/** A slot expanded onto one date. */
data class Lesson(
    val date: String,
    val weekday: Int,
    val session: String,
    val period: Int,
    val classId: String,
    val teacherId: String,
    val subjectId: String,
) {
    /** `morning-3`: one lesson per class per cell and date. */
    val cellKey: String get() = "$session-$period"
}

/** The calendar of a school year (dates `YYYY-MM-DD`, Vietnam calendar). */
data class YearWindow(val startDate: String, val endDate: String)

data class VietnamNow(val date: String, val time: String)

/**
 * Client mirror of src/lib/teachingSchedule.js (itself a mirror of convex/teachingPolicy.ts):
 * the weekly timetable is expanded onto real dates, skipping weekends, holidays and days outside the year.
 */
object TeachingSchedule {
    val WEEKDAYS = listOf(1, 2, 3, 4, 5)
    val SESSIONS = listOf("morning", "afternoon")
    val PERIODS = listOf(1, 2, 3, 4, 5)
    private val PERIOD_START_TIMES = mapOf(
        "morning" to listOf("07:00", "07:50", "08:50", "09:40", "10:30"),
        "afternoon" to listOf("13:30", "14:20", "15:20", "16:10", "17:00"),
    )
    const val PERIOD_MINUTES = 45
    /** How far "Lớp giảng dạy" looks for the next lesson of a class. */
    const val NEXT_LESSON_LOOKAHEAD_DAYS = 35L
    private val VIETNAM: ZoneId = ZoneId.of("Asia/Ho_Chi_Minh")

    fun weekdayLabel(weekday: Int): String = when (weekday) {
        in 1..6 -> "Thứ ${weekday + 1}"
        7 -> "Chủ nhật"
        else -> ""
    }

    fun sessionLabel(session: String): String = if (session == "afternoon") "Chiều" else "Sáng"

    /** "Tiết 3 sáng", "Tiết 1 chiều". */
    fun periodLabel(session: String, period: Int): String = "Tiết $period ${sessionLabel(session).lowercase()}"

    fun isoWeekday(date: String): Int = LocalDate.parse(date).dayOfWeek.value

    fun addDays(date: String, days: Long): String = LocalDate.parse(date).plusDays(days).toString()

    /** Monday of the week containing [date]. */
    fun weekStart(date: String): String = addDays(date, (1 - isoWeekday(date)).toLong())

    fun monthStart(date: String): String = "${date.take(7)}-01"

    fun monthEnd(date: String): String = LocalDate.parse(monthStart(date)).plusMonths(1).minusDays(1).toString()

    fun addMonths(date: String, months: Long): String = LocalDate.parse(monthStart(date)).plusMonths(months).toString()

    fun slotCoversDate(slot: TimetableSlot, date: String): Boolean =
        slot.effectiveFrom <= date && (slot.effectiveTo.isNullOrBlank() || date <= slot.effectiveTo)

    fun isTimetableDay(date: String, year: YearWindow, holidays: Set<String>): Boolean {
        if (date < year.startDate || date > year.endDate) return false
        if (isoWeekday(date) > 5) return false
        return date !in holidays
    }

    fun lessonStartTime(session: String, period: Int): String {
        val times = PERIOD_START_TIMES[session] ?: PERIOD_START_TIMES.getValue("morning")
        return times.getOrNull(period - 1) ?: "00:00"
    }

    fun lessonStartTime(lesson: Lesson): String = lessonStartTime(lesson.session, lesson.period)

    /** 45-minute periods. */
    fun lessonEndTime(lesson: Lesson): String {
        val (hours, minutes) = lessonStartTime(lesson).split(":").map { it.toInt() }
        val total = hours * 60 + minutes + PERIOD_MINUTES
        return "%02d:%02d".format(total / 60, total % 60)
    }

    val lessonOrder: Comparator<Lesson> = Comparator { a, b ->
        when {
            a.date != b.date -> a.date.compareTo(b.date)
            else -> lessonStartTime(a).compareTo(lessonStartTime(b)).takeIf { it != 0 } ?: (a.period - b.period)
        }
    }

    fun expandLessons(
        slots: List<TimetableSlot>,
        from: String,
        to: String,
        year: YearWindow,
        holidays: Set<String>,
    ): List<Lesson> {
        val start = if (from < year.startDate) year.startDate else from
        val end = if (to > year.endDate) year.endDate else to
        if (start > end) return emptyList()
        val lessons = mutableListOf<Lesson>()
        var date = start
        while (date <= end) {
            if (isTimetableDay(date, year, holidays)) {
                val weekday = isoWeekday(date)
                for (slot in slots) {
                    if (slot.weekday != weekday || !slotCoversDate(slot, date)) continue
                    lessons += Lesson(date, weekday, slot.session, slot.period, slot.classId, slot.teacherId, slot.subjectId)
                }
            }
            date = addDays(date, 1)
        }
        return lessons.sortedWith(lessonOrder)
    }

    /**
     * Next lesson per class from [now]: a lesson already started today counts until it ends, so the class
     * being taught stays first; otherwise the first lesson of a later day.
     */
    fun nextLessonByClass(lessons: List<Lesson>, now: VietnamNow): Map<String, Lesson> {
        val next = linkedMapOf<String, Lesson>()
        for (lesson in lessons.sortedWith(lessonOrder)) {
            if (lesson.date < now.date) continue
            if (lesson.date == now.date && lessonEndTime(lesson) < now.time) continue
            next.putIfAbsent(lesson.classId, lesson)
        }
        return next
    }

    /**
     * Default lesson of the Sổ đầu bài form: the one being / just taught (latest start ≤ now) on today,
     * any lesson on a past date (the last of the day), else the first of the day.
     */
    fun defaultLesson(lessons: List<Lesson>, date: String, now: VietnamNow): Lesson? =
        lessons.lastOrNull { date < now.date || lessonStartTime(it) <= now.time } ?: lessons.firstOrNull()

    fun vietnamNow(now: Instant = Instant.now()): VietnamNow {
        val local = now.atZone(VIETNAM)
        return VietnamNow(local.toLocalDate().toString(), local.format(DateTimeFormatter.ofPattern("HH:mm")))
    }

    /** Học kỳ II from `semester2StartDate` on; a year without that date is all Học kỳ I. */
    fun semesterForDate(date: String, semester2StartDate: String?): Int =
        if (!semester2StartDate.isNullOrBlank() && date >= semester2StartDate) 2 else 1

    /** dd/MM/yyyy. */
    fun formatDate(date: String): String = runCatching {
        val value = LocalDate.parse(date)
        "%02d/%02d/%04d".format(value.dayOfMonth, value.monthValue, value.year)
    }.getOrDefault(date)

    /** "Thứ 4, 21/10/2026". */
    fun dayTitle(date: String): String = "${weekdayLabel(isoWeekday(date))}, ${formatDate(date)}"

    /** "Tháng 10/2026". */
    fun monthLabel(date: String): String {
        val value = LocalDate.parse(monthStart(date))
        return "Tháng ${value.monthValue}/${value.year}"
    }

    /** Natural "6A2" < "6A10" ordering used by the web class lists. */
    val naturalOrder: Comparator<String> = Comparator { a, b -> naturalCompare(a, b) }

    fun naturalCompare(a: String, b: String): Int {
        val tokens = Regex("\\d+|\\D+")
        val left = tokens.findAll(a.lowercase()).map { it.value }.toList()
        val right = tokens.findAll(b.lowercase()).map { it.value }.toList()
        for (index in 0 until minOf(left.size, right.size)) {
            val x = left[index]
            val y = right[index]
            val compared = if (x.first().isDigit() && y.first().isDigit()) {
                x.toBigInteger().compareTo(y.toBigInteger())
            } else {
                x.compareTo(y)
            }
            if (compared != 0) return compared
        }
        return left.size - right.size
    }
}

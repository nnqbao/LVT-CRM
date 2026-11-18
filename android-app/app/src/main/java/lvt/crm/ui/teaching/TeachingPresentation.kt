package lvt.crm.ui.teaching

import lvt.crm.data.teaching.ClassLessonLog
import lvt.crm.data.teaching.GradeMath
import lvt.crm.data.teaching.Lesson
import lvt.crm.data.teaching.MyTeaching
import lvt.crm.data.teaching.TeachingCatalog
import lvt.crm.data.teaching.TeachingClass
import lvt.crm.data.teaching.TeachingSchedule
import lvt.crm.data.teaching.VietnamNow

/** One row of "Lớp giảng dạy". */
data class TeachingClassRow(
    val klass: TeachingClass,
    val subjects: String,
    val next: Lesson?,
    val isToday: Boolean,
    val nextLabel: String,
)

/** A lesson of today on the Tổng quan card. */
data class TodayLessonRow(val lesson: Lesson, val title: String, val time: String, val period: String, val logged: Boolean)

enum class ScheduleView(val label: String) { List("Danh sách"), Week("Tuần"), Month("Tháng") }

data class ScheduleRange(val from: String, val to: String, val label: String)

/** Pure wording / ordering for Lớp học (mirrors src/teaching/TeachingViews.jsx). Unit-tested. */
object TeachingPresentation {
    fun classNames(classes: List<TeachingClass>): Map<String, String> = classes.associate { it.id to it.name }

    fun todayLessons(data: MyTeaching, catalog: TeachingCatalog?, now: VietnamNow): List<TodayLessonRow> {
        val names = classNames(data.classes)
        val logged = data.todayLogs.mapTo(mutableSetOf()) { "${it.classId}-${it.session}-${it.period}" }
        return TeachingSchedule.expandLessons(data.slots, now.date, now.date, data.year.window, data.holidays).map { lesson ->
            TodayLessonRow(
                lesson = lesson,
                title = "${names[lesson.classId] ?: "Lớp"} · ${catalog?.subjectName(lesson.subjectId) ?: "Môn học"}",
                time = TeachingSchedule.lessonStartTime(lesson),
                period = TeachingSchedule.periodLabel(lesson.session, lesson.period),
                logged = "${lesson.classId}-${lesson.session}-${lesson.period}" in logged,
            )
        }
    }

    /** Classes the teacher teaches, the nearest next lesson first; classes without one last, by name. */
    fun teachingRows(data: MyTeaching, catalog: TeachingCatalog?, now: VietnamNow): List<TeachingClassRow> {
        val lessons = TeachingSchedule.expandLessons(
            data.slots,
            now.date,
            TeachingSchedule.addDays(now.date, TeachingSchedule.NEXT_LESSON_LOOKAHEAD_DAYS),
            data.year.window,
            data.holidays,
        )
        val next = TeachingSchedule.nextLessonByClass(lessons, now)
        val subjectsByClass = linkedMapOf<String, LinkedHashSet<String>>()
        for (slot in data.slots) subjectsByClass.getOrPut(slot.classId) { linkedSetOf() }.add(slot.subjectId)
        return data.classes
            .map { klass ->
                val lesson = next[klass.id]
                val isToday = lesson?.date == now.date
                TeachingClassRow(
                    klass = klass,
                    subjects = subjectsByClass[klass.id].orEmpty().joinToString(", ") { catalog?.subjectName(it) ?: "Môn học" },
                    next = lesson,
                    isToday = isToday,
                    nextLabel = nextLessonLabel(lesson, now),
                )
            }
            .sortedWith { a, b ->
                val left = a.next
                val right = b.next
                when {
                    left != null && right != null ->
                        "${left.date} ${TeachingSchedule.lessonStartTime(left)}".compareTo("${right.date} ${TeachingSchedule.lessonStartTime(right)}")
                    left != null -> -1
                    right != null -> 1
                    else -> TeachingSchedule.naturalCompare(a.klass.name, b.klass.name)
                }
            }
    }

    fun nextLessonLabel(lesson: Lesson?, now: VietnamNow): String {
        if (lesson == null) return "Không còn tiết nào trong 5 tuần tới"
        val day = if (lesson.date == now.date) "Hôm nay" else TeachingSchedule.dayTitle(lesson.date)
        return "$day · ${TeachingSchedule.periodLabel(lesson.session, lesson.period)} · ${TeachingSchedule.lessonStartTime(lesson)}"
    }

    /** Lessons of one class on one date for the Sổ đầu bài form. */
    fun lessonsOfClass(data: MyTeaching, classId: String, date: String): List<Lesson> =
        TeachingSchedule.expandLessons(data.slots.filter { it.classId == classId }, date, date, data.year.window, data.holidays)

    /** Last selectable date of the Sổ đầu bài form: today, clamped into the year. */
    fun lessonLogMaxDate(data: MyTeaching, now: VietnamNow): String =
        if (now.date > data.year.endDate) data.year.endDate else now.date

    /** "4,3/5 sao" for a week of lesson logs; empty when there is none. */
    fun weeklyAverage(logs: List<ClassLessonLog>): String {
        if (logs.isEmpty()) return ""
        val average = logs.sumOf { it.rating }.toDouble() / logs.size
        return "%.1f".format(java.util.Locale.ROOT, average).replace('.', ',')
    }

    fun starsLabel(rating: Int): String = "$rating trên 5 sao"

    fun scheduleRange(view: ScheduleView, anchor: String): ScheduleRange = when (view) {
        ScheduleView.Week -> {
            val from = TeachingSchedule.weekStart(anchor)
            val to = TeachingSchedule.addDays(from, 4)
            ScheduleRange(from, to, "Tuần ${TeachingSchedule.formatDate(from).take(5)} – ${TeachingSchedule.formatDate(to)}")
        }
        ScheduleView.List, ScheduleView.Month -> ScheduleRange(
            TeachingSchedule.monthStart(anchor),
            TeachingSchedule.monthEnd(anchor),
            TeachingSchedule.monthLabel(anchor),
        )
    }

    fun shiftAnchor(view: ScheduleView, anchor: String, delta: Int): String = when (view) {
        ScheduleView.Week -> TeachingSchedule.addDays(anchor, 7L * delta)
        else -> TeachingSchedule.addMonths(anchor, delta.toLong())
    }

    fun clampDate(date: String, startDate: String, endDate: String): String = when {
        date < startDate -> startDate
        date > endDate -> endDate
        else -> date
    }

    /** Calendar cells (Thứ 2–6) of a month, starting at the Monday of the first week. */
    fun monthCells(from: String, to: String): List<String> {
        val cells = mutableListOf<String>()
        var date = TeachingSchedule.weekStart(from)
        while (date <= to) {
            if (TeachingSchedule.isoWeekday(date) <= 5) cells += date
            date = TeachingSchedule.addDays(date, 1)
        }
        return cells
    }

    /** Short cell text in the month view: "S3 · 6A1". */
    fun monthLessonText(lesson: Lesson, className: String): String =
        "${if (lesson.session == "morning") "S" else "C"}${lesson.period} · $className"

    fun scoreLabel(value: Double?): String = GradeMath.formatScore(value)
}

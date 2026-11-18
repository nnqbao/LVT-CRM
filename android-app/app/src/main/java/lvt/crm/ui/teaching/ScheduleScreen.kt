package lvt.crm.ui.teaching

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import lvt.crm.data.teaching.Lesson
import lvt.crm.data.teaching.TeacherSchedule
import lvt.crm.data.teaching.TeachingCatalog
import lvt.crm.data.teaching.TeachingSchedule
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.homeroom.HomeroomTone
import lvt.crm.ui.homeroom.ListSegment
import lvt.crm.ui.homeroom.toneColors

/** Lịch dạy của tôi: Danh sách (theo tháng), Tuần (Thứ 2–6 × 10 tiết), Tháng. Mirrors ScheduleCalendar.jsx. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleContent(
    schedule: TeacherSchedule?,
    loading: Boolean,
    error: String?,
    catalog: TeachingCatalog?,
    today: String,
    onRetry: () -> Unit,
) {
    when {
        schedule == null && error != null -> {
            Column(Modifier.padding(16.dp)) { ErrorBlock(error, onRetry) }
            return
        }
        schedule == null -> {
            Column(Modifier.padding(16.dp)) { if (loading) LoadingRow("Đang tải lịch dạy…") }
            return
        }
    }
    val data = schedule!!
    var view by rememberSaveable { mutableStateOf(ScheduleView.List) }
    val todayInYear = TeachingPresentation.clampDate(today, data.year.startDate, data.year.endDate)
    var anchor by rememberSaveable(data.year.id) { mutableStateOf(todayInYear) }
    val range = TeachingPresentation.scheduleRange(view, anchor)
    val lessons = remember(data, range) {
        TeachingSchedule.expandLessons(data.slots, range.from, range.to, data.year.window, data.holidays)
    }
    val classNames = remember(data) { TeachingPresentation.classNames(data.classes) }
    val describe = { lesson: Lesson ->
        "${classNames[lesson.classId] ?: "Lớp"} · ${catalog?.subjectName(lesson.subjectId) ?: "Môn học"}"
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                ScheduleView.entries.forEachIndexed { index, option ->
                    SegmentedButton(
                        selected = view == option,
                        onClick = { view = option },
                        shape = SegmentedButtonDefaults.itemShape(index, ScheduleView.entries.size),
                    ) { Text(option.label) }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                PeriodStepper(
                    label = range.label,
                    canPrevious = range.from > data.year.startDate,
                    canNext = range.to < data.year.endDate,
                    onPrevious = { anchor = TeachingPresentation.shiftAnchor(view, anchor, -1) },
                    onNext = { anchor = TeachingPresentation.shiftAnchor(view, anchor, 1) },
                    previousLabel = if (view == ScheduleView.Week) "Tuần trước" else "Tháng trước",
                    nextLabel = if (view == ScheduleView.Week) "Tuần sau" else "Tháng sau",
                    modifier = Modifier.weight(1f),
                )
                if (anchor != todayInYear) {
                    TextButton(onClick = { anchor = todayInYear }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Hôm nay") }
                }
            }
        }
        if (data.slots.isEmpty()) {
            StatePanel(
                icon = Icons.Outlined.CalendarMonth,
                title = "Chưa có lịch dạy trong năm học này.",
                message = "Quản trị viên xếp lịch tại Thiết lập giáo viên hoặc Thiết lập lịch dạy (bản web).",
            )
            return
        }
        when (view) {
            ScheduleView.List -> ScheduleList(lessons, describe, today)
            ScheduleView.Week -> ScheduleWeek(range.from, lessons, data, classNames, catalog)
            ScheduleView.Month -> ScheduleMonth(range.from, range.to, lessons, data, classNames, today)
        }
    }
}

@Composable
private fun ScheduleList(lessons: List<Lesson>, describe: (Lesson) -> String, today: String) {
    val days = lessons.groupBy { it.date }.entries.toList()
    if (days.isEmpty()) {
        StatePanel(icon = Icons.Outlined.CalendarMonth, title = "Không có tiết dạy trong tháng này.", message = "Dùng nút ‹ › để xem tháng khác.")
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(days, key = { it.key }) { (date, rows) ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(TeachingSchedule.dayTitle(date), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    MutedText("${if (date == today) "Hôm nay · " else ""}${rows.size} tiết")
                }
                rows.forEachIndexed { index, lesson ->
                    ListSegment(index, rows.size) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text(TeachingSchedule.periodLabel(lesson.session, lesson.period), fontWeight = FontWeight.SemiBold, modifier = Modifier.width(96.dp))
                            Text(describe(lesson), modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                            MutedText(TeachingSchedule.lessonStartTime(lesson))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScheduleWeek(
    from: String,
    lessons: List<Lesson>,
    data: TeacherSchedule,
    classNames: Map<String, String>,
    catalog: TeachingCatalog?,
) {
    val dates = TeachingSchedule.WEEKDAYS.map { TeachingSchedule.addDays(from, (it - 1).toLong()) }
    val byKey = lessons.associateBy { "${it.date}-${it.session}-${it.period}" }
    val mine = toneColors(HomeroomTone.Info)
    val labelWidth = 64.dp
    val cellWidth = 72.dp
    val line = MaterialTheme.colorScheme.outlineVariant
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 16.dp)) {
        item {
            Column(Modifier.horizontalScroll(rememberScrollState())) {
                Row {
                    Box(Modifier.width(labelWidth).padding(4.dp)) { MutedText("Tiết") }
                    dates.forEach { date ->
                        Column(Modifier.width(cellWidth).padding(4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(TeachingSchedule.weekdayLabel(TeachingSchedule.isoWeekday(date)), fontWeight = FontWeight.Bold, fontSize = 13.sp)
                            MutedText(TeachingSchedule.formatDate(date).take(5))
                        }
                    }
                }
                TeachingSchedule.SESSIONS.forEach { session ->
                    HorizontalDivider(color = if (session == "afternoon") MaterialTheme.colorScheme.outline else line)
                    TeachingSchedule.PERIODS.forEach { period ->
                        Row(Modifier.height(56.dp)) {
                            Column(Modifier.width(labelWidth).padding(4.dp)) {
                                Text("Tiết $period", fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                                Text(
                                    "${TeachingSchedule.sessionLabel(session)} ${TeachingSchedule.lessonStartTime(session, period)}",
                                    fontSize = 12.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            dates.forEach { date ->
                                val lesson = byKey["$date-$session-$period"]
                                val off = date in data.holidays || date < data.year.startDate || date > data.year.endDate
                                Box(Modifier.width(cellWidth).padding(2.dp)) {
                                    when {
                                        lesson != null -> Column(
                                            Modifier
                                                .fillMaxSize()
                                                .clip(RoundedCornerShape(8.dp))
                                                .background(mine.background)
                                                .padding(4.dp)
                                                .semantics(mergeDescendants = true) {
                                                    contentDescription = "${TeachingSchedule.dayTitle(date)}, ${TeachingSchedule.periodLabel(session, period)}: ${classNames[lesson.classId] ?: "Lớp"}, ${catalog?.subjectName(lesson.subjectId) ?: ""}"
                                                },
                                        ) {
                                            Text(classNames[lesson.classId] ?: "Lớp", color = mine.text, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                            Text(catalog?.subjectName(lesson.subjectId).orEmpty(), color = mine.text, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        }
                                        off && session == "morning" && period == 1 -> Text("Nghỉ", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, modifier = Modifier.padding(4.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScheduleMonth(
    from: String,
    to: String,
    lessons: List<Lesson>,
    data: TeacherSchedule,
    classNames: Map<String, String>,
    today: String,
) {
    val byDate = lessons.groupBy { it.date }
    val cells = TeachingPresentation.monthCells(from, to)
    val outline = MaterialTheme.colorScheme.primary
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 16.dp)) {
        item {
            Row(Modifier.fillMaxWidth()) {
                TeachingSchedule.WEEKDAYS.forEach { weekday ->
                    Text(
                        TeachingSchedule.weekdayLabel(weekday),
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f).padding(vertical = 4.dp),
                    )
                }
            }
        }
        items(cells.chunked(5)) { week ->
            Row(Modifier.fillMaxWidth().heightIn(min = 72.dp)) {
                week.forEach { date ->
                    val outside = date < from
                    val off = date in data.holidays || date < data.year.startDate || date > data.year.endDate
                    val rows = if (outside) emptyList() else byDate[date].orEmpty()
                    Column(
                        Modifier
                            .weight(1f)
                            .padding(2.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(
                                if (outside) MaterialTheme.colorScheme.surface
                                else if (off) MaterialTheme.colorScheme.surfaceVariant
                                else MaterialTheme.colorScheme.surfaceContainerLow,
                            )
                            .then(if (date == today) Modifier.border(2.dp, outline, RoundedCornerShape(8.dp)) else Modifier)
                            .padding(4.dp),
                    ) {
                        if (!outside) {
                            Text(
                                date.takeLast(2).trimStart('0'),
                                fontWeight = FontWeight.Bold,
                                fontSize = 13.sp,
                                color = if (date == today) outline else MaterialTheme.colorScheme.onSurface,
                            )
                            if (off) Text("Nghỉ", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            rows.forEach { lesson ->
                                Text(
                                    TeachingPresentation.monthLessonText(lesson, classNames[lesson.classId] ?: "Lớp"),
                                    fontSize = 12.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Clip,
                                )
                            }
                        }
                    }
                }
                repeat(5 - week.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
}

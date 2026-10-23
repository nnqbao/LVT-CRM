package lvt.crm.ui.teaching

import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import lvt.crm.data.homeroom.HomeroomOverview
import lvt.crm.data.teaching.TeachingSchedule
import lvt.crm.ui.homeroom.HomeroomBanner
import lvt.crm.ui.homeroom.HomeroomChip
import lvt.crm.ui.homeroom.HomeroomListRow
import lvt.crm.ui.homeroom.HomeroomTone
import lvt.crm.ui.homeroom.ListSegment
import lvt.crm.ui.homeroom.toneColors
import lvt.crm.ui.components.StatePanel

// ------------------------------------------------------------------ Tổng quan

@Composable
fun TeachingOverviewContent(
    state: TeachingUiState,
    onOpenTeaching: () -> Unit,
    onOpenHomeroom: () -> Unit,
    onOpenHomeroomClass: (String) -> Unit,
) {
    val teaching = state.teaching
    val today = state.now.date
    val lessons = remember(teaching, state.catalog, state.now) {
        teaching?.let { TeachingPresentation.todayLessons(it, state.catalog, state.now) }.orEmpty()
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "today-lessons") {
            TeachingCard(
                eyebrow = "Lớp giảng dạy",
                title = "Tiết dạy hôm nay",
                subtitle = TeachingSchedule.dayTitle(today),
                action = { DetailButton(onOpenTeaching) },
            ) {
                when {
                    teaching == null -> LoadingRow("Đang tải tiết dạy…")
                    lessons.isEmpty() -> EmptyNote(
                        "Hôm nay bạn không có tiết dạy.",
                        if (teaching.slots.isNotEmpty()) "Xem lịch các ngày khác ở mục Lịch dạy." else "Bạn chưa được xếp lịch dạy trong năm học này.",
                    )
                    else -> Column {
                        lessons.forEachIndexed { index, row ->
                            ListSegment(index, lessons.size) {
                                HomeroomListRow(
                                    title = row.title,
                                    subtitle = row.period,
                                    chips = listOf(
                                        if (row.logged) HomeroomChip("Đã ghi sổ", HomeroomTone.Success)
                                        else HomeroomChip("Chưa ghi sổ", HomeroomTone.Warning),
                                    ),
                                    leading = row.time,
                                )
                            }
                        }
                    }
                }
            }
        }
        item(key = "absent-today") {
            TeachingCard(
                eyebrow = "Lớp chủ nhiệm",
                title = "Học sinh vắng hôm nay",
                subtitle = "Vào lớp để đánh dấu vắng có phép hay không phép.",
                action = { DetailButton(onOpenHomeroom) },
            ) {
                AbsentTodayContent(state.homeroomOverview, state.homeroomError, state.loading, onOpenHomeroomClass)
            }
        }
    }
}

@Composable
private fun AbsentTodayContent(
    overview: HomeroomOverview?,
    error: String?,
    loading: Boolean,
    onOpenClass: (String) -> Unit,
) {
    when {
        overview == null && error != null -> MutedText(error)
        overview == null -> if (loading) LoadingRow("Đang tải điểm danh…") else MutedText("Chưa có dữ liệu điểm danh hôm nay.")
        overview.mode == "school" -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            val counts = overview.counts
            Text("Toàn trường có ${counts.absent} học sinh vắng (${counts.absentExcused} có phép · ${counts.absentUnexcused} không phép).")
            MutedText("${overview.classes.count { it.saved }}/${overview.classes.size} lớp đã được điểm danh.")
        }
        overview.classes.isEmpty() -> EmptyNote("Bạn không chủ nhiệm lớp nào trong năm học này.", null)
        else -> Column {
            overview.classes.forEachIndexed { index, row ->
                ListSegment(index, overview.classes.size) {
                    HomeroomListRow(
                        title = row.name.ifBlank { "Lớp ${row.code}" },
                        subtitle = if (row.saved) {
                            "${row.counts.absentExcused} có phép · ${row.counts.absentUnexcused} không phép · sĩ số ${row.rosterCount}"
                        } else {
                            "Sĩ số ${row.rosterCount}"
                        },
                        chips = listOf(
                            when {
                                !row.saved -> HomeroomChip("Chưa điểm danh", HomeroomTone.Neutral)
                                row.counts.absent > 0 -> HomeroomChip("${row.counts.absent} em vắng", HomeroomTone.Danger)
                                else -> HomeroomChip("Đủ", HomeroomTone.Success)
                            },
                        ),
                        onClick = { onOpenClass(row.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailButton(onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.heightIn(min = 48.dp)) {
        Text("Xem chi tiết")
        Icon(Icons.AutoMirrored.Outlined.ArrowForward, contentDescription = null, modifier = Modifier.padding(start = 4.dp).size(16.dp))
    }
}

@Composable
private fun EmptyNote(title: String, message: String?) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, fontWeight = FontWeight.SemiBold)
        if (message != null) MutedText(message)
    }
}

// ------------------------------------------------------------------ Lớp giảng dạy

@Composable
fun TeachingClassesContent(state: TeachingUiState, onOpen: (String) -> Unit) {
    val teaching = state.teaching ?: return
    val rows = remember(teaching, state.catalog, state.now) {
        TeachingPresentation.teachingRows(teaching, state.catalog, state.now)
    }
    if (rows.isEmpty()) {
        StatePanel(
            icon = Icons.Outlined.Groups,
            title = "Bạn chưa được xếp lịch dạy trong năm học này.",
            message = "Quản trị viên xếp lịch tại Thiết lập giáo viên hoặc Thiết lập lịch dạy (bản web).",
        )
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item(key = "hint") {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                MutedText("Bấm vào lớp để ghi Sổ đầu bài cho tiết vừa dạy. Giáo viên chủ nhiệm của lớp sẽ thấy đánh giá này.")
                state.message?.let { Text(it, color = toneColors(HomeroomTone.Success).text, fontWeight = FontWeight.SemiBold) }
                if (teaching.year.locked) HomeroomBanner("Năm học đã khóa", "Không ghi thêm Sổ đầu bài.", HomeroomTone.Warning, Icons.Outlined.Lock)
            }
        }
        itemsIndexed(rows, key = { _, row -> row.klass.id }) { index, row ->
            ListSegment(index, rows.size) {
                TeachingClassRowView(row, onClick = { onOpen(row.klass.id) })
            }
        }
    }
}

@Composable
private fun TeachingClassRowView(row: TeachingClassRow, onClick: () -> Unit) {
    val highlight = if (row.isToday) toneColors(HomeroomTone.Info).background.copy(alpha = 0.6f) else MaterialTheme.colorScheme.surfaceContainerLow
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(highlight)
            .clickable(onClick = onClick)
            .heightIn(min = 64.dp)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(row.klass.name, fontWeight = FontWeight.Bold)
            if (row.subjects.isNotBlank()) MutedText(row.subjects)
            Text(row.nextLabel, style = MaterialTheme.typography.bodySmall, fontWeight = if (row.isToday) FontWeight.SemiBold else FontWeight.Normal)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.EditNote, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
            Text("Sổ đầu bài", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(start = 4.dp))
        }
    }
}

// ------------------------------------------------------------------ Sổ đầu bài sheet

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LessonLogSheet(state: TeachingUiState, viewModel: TeachingViewModel) {
    val form = state.form ?: return
    val teaching = state.teaching ?: return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val locked = teaching.year.locked
    val current = form.current
    val subjectName = current?.let { state.catalog?.subjectName(it.subjectId) } ?: "Môn học"
    val maxDate = TeachingPresentation.lessonLogMaxDate(teaching, state.now)
    val context = LocalContext.current
    ModalBottomSheet(onDismissRequest = { if (!form.saving) viewModel.closeLessonLog() }, sheetState = sheetState) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .navigationBarsPadding()
                .padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column {
                Text("Sổ đầu bài · ${form.className}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                MutedText(
                    if (current != null) {
                        "${TeachingSchedule.periodLabel(current.session, current.period)} · $subjectName · ${TeachingSchedule.formatDate(form.date)}"
                    } else {
                        TeachingSchedule.formatDate(form.date)
                    },
                )
            }
            FieldLabel("Ngày dạy")
            OutlinedButton(
                onClick = {
                    val selected = LocalDate.parse(form.date)
                    DatePickerDialog(
                        context,
                        { _, year, month, day -> viewModel.selectLogDate(LocalDate.of(year, month + 1, day).toString()) },
                        selected.year,
                        selected.monthValue - 1,
                        selected.dayOfMonth,
                    ).apply {
                        datePicker.minDate = epochMillis(teaching.year.startDate)
                        datePicker.maxDate = epochMillis(maxDate, endOfDay = true)
                    }.show()
                },
                enabled = !form.saving,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                Icon(Icons.Outlined.CalendarMonth, contentDescription = null, modifier = Modifier.padding(end = 8.dp))
                Text(TeachingSchedule.dayTitle(form.date))
            }
            FieldLabel("Tiết")
            if (form.lessons.isEmpty()) {
                HomeroomBanner(
                    "Ngày này bạn không có tiết ở lớp này.",
                    "Chọn ngày khác có tiết dạy để ghi sổ.",
                    HomeroomTone.Info,
                    Icons.Outlined.EventBusy,
                )
            } else {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    form.lessons.forEach { lesson ->
                        FilterChip(
                            selected = lesson.cellKey == form.cell,
                            onClick = { viewModel.selectLogCell(lesson.cellKey) },
                            enabled = !form.saving,
                            label = { Text("${TeachingSchedule.periodLabel(lesson.session, lesson.period)} · ${TeachingSchedule.lessonStartTime(lesson)}") },
                            modifier = Modifier.heightIn(min = 48.dp),
                        )
                    }
                }
            }
            when {
                form.existing == null -> LoadingRow("Đang tải Sổ đầu bài đã ghi…")
                form.saved != null -> Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = toneColors(HomeroomTone.Success).text, modifier = Modifier.size(16.dp))
                    MutedText("Đã ghi lúc ${formatTimestamp(form.saved!!.updatedAt)} — lưu lại để sửa.", Modifier.padding(start = 6.dp))
                }
            }
            FieldLabel("Đánh giá tiết học")
            StarRatingInput(
                rating = form.rating,
                enabled = current != null && !locked && !form.saving,
                onRate = viewModel::setRating,
            )
            OutlinedTextField(
                value = form.comment,
                onValueChange = viewModel::setComment,
                label = { Text("Nhận xét tiết học") },
                enabled = current != null && !locked && !form.saving,
                minLines = 3,
                supportingText = { Text("${form.comment.length}/${TeachingViewModel.LESSON_COMMENT_MAX}") },
                modifier = Modifier.fillMaxWidth(),
            )
            if (locked) HomeroomBanner("Năm học đã khóa — không ghi thêm Sổ đầu bài.", null, HomeroomTone.Warning, Icons.Outlined.Lock)
            form.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = viewModel::closeLessonLog,
                    enabled = !form.saving,
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                ) { Text("Đóng") }
                Button(
                    onClick = viewModel::saveLessonLog,
                    enabled = current != null && form.rating in 1..5 && !locked && form.existing != null && !form.saving,
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                ) { Text(if (form.saving) "Đang lưu…" else "Lưu") }
            }
            Spacer(Modifier.heightIn(min = 8.dp))
        }
    }
}

@Composable
internal fun FieldLabel(text: String) {
    Text(text, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
}

/** Start of [date] (or its last millisecond when [endOfDay]) in the device zone, for DatePicker bounds. */
internal fun epochMillis(date: String, endOfDay: Boolean = false): Long {
    val start = LocalDate.parse(date).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
    return if (endOfDay) start + 86_399_999 else start
}

internal fun formatTimestamp(milliseconds: Double): String =
    DateTimeFormatter.ofPattern("HH:mm dd/MM/yyyy")
        .withZone(ZoneId.of("Asia/Ho_Chi_Minh"))
        .format(Instant.ofEpochMilli(milliseconds.toLong()))

package lvt.crm.ui.homeroom

import android.app.DatePickerDialog
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.Alignment
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import lvt.crm.data.homeroom.*
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.GuideAnchors

@Composable
fun HomeroomDetailScreen(
    viewModel: HomeroomDetailViewModel,
    onClose: () -> Unit,
    classLogsLoader: lvt.crm.ui.teaching.ClassLogsLoader? = null,
) {
    val state by viewModel.uiState.collectAsState()
    var tab by remember { mutableStateOf(DetailTab.Daily) }
    val daily = tab == DetailTab.Daily
    val logs = rememberClassLessonLogs(state.context.classId, tab == DetailTab.LessonLogs, classLogsLoader)
    var search by remember { mutableStateOf("") }
    var contactForm by remember(state.context, state.studentId) { mutableStateOf<HomeroomForm?>(null) }
    contactForm?.let { draft -> viewModel.writeOperations?.let { writes -> HomeroomWriteForm(draft, writes, { viewModel.uiState.value.context == draft.context && viewModel.uiState.value.studentId == draft.studentId && viewModel.uiState.value.error == null }, viewModel::clearWriteData, viewModel::refresh) { contactForm = null } } }
    val back = { if (state.studentId != null) viewModel.backToClass() else onClose() }
    BackHandler(onBack = back)
    LvtScreen(title = if (state.studentId != null) "Học sinh" else "Lớp", refreshing = state.loading || state.refreshing, onRefresh = viewModel::refresh, showAccountHeader = true, helpAnchor = GuideAnchors.HOMEROOM) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                OutlinedButton(onClick = back, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(if (state.studentId != null) "Trở lại lớp" else "Trở lại tổng quan") }
            }
            if (state.studentId == null) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        DayNavigator(date = state.context.date, onDate = viewModel::selectDate)
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            DetailTab.entries.filter { it != DetailTab.LessonLogs || classLogsLoader != null }.forEach { option ->
                                FilterChip(selected = tab == option, onClick = { tab = option }, label = { Text(option.label, maxLines = 1) }, modifier = Modifier.heightIn(min = 48.dp))
                            }
                        }
                        if (tab != DetailTab.LessonLogs) {
                            OutlinedTextField(value = search, onValueChange = { search = it }, label = { Text("Tìm học sinh") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                        }
                    }
                }
            } else {
                item {
                    HistoryDateButton("Lịch sử từ", state.context.from) { viewModel.selectHistoryRange(it, state.context.to) }
                    HistoryDateButton("Lịch sử đến", state.context.to) { viewModel.selectHistoryRange(state.context.from, it) }
                    Text("Ngày bắt đầu không được sau ngày kết thúc.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                }
            }
            when {
                state.loading && state.classData == null && state.studentData == null -> item { CircularProgressIndicator(); Text("Đang tải…") }
                state.error != null -> item {
                    DetailCard("Chưa tải được dữ liệu", "${state.error}")
                    Button(onClick = viewModel::refresh, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Thử lại") }
                }
                state.classData != null -> {
                    val data = state.classData!!
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(data.scoped.name.ifBlank { "Lớp ${data.scoped.code}" }, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
                            Text(
                                listOfNotNull(HomeroomPresentation.dayTitle(state.context.date), "GVCN ${data.scoped.teacherName.ifBlank { "chưa phân công" }}", if (data.scoped.status == "archived") "Lớp đã lưu trữ" else null).joinToString(" · "),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                    if (tab == DetailTab.LessonLogs) {
                        classLessonLogItems(logs)
                    } else if (daily) {
                        dailyAttendanceItems(state, data, canWrite = viewModel.writeOperations != null, search = search, onOpenStudent = viewModel::openStudent, onToggle = viewModel::setUnexcused)
                    } else {
                        val rows = data.roster.rows.filter { matchesStudent(it.student, search) }
                        item {
                            Text("${rows.size} học sinh", fontWeight = FontWeight.SemiBold)
                            if (rows.isEmpty()) Text(if (data.roster.rows.isEmpty()) "Lớp chưa có học sinh." else "Không tìm thấy học sinh.")
                        }
                        itemsIndexed(rows, key = { _, row -> row.student.id }) { index, row ->
                            ListSegment(index, rows.size) {
                                HomeroomListRow(
                                    title = row.student.fullName,
                                    subtitle = "Mã ${row.student.studentCode}",
                                    chips = emptyList(),
                                    leading = row.enrollment.rosterNumber?.toString() ?: "—",
                                    onClick = { viewModel.openStudent(row.student.id) },
                                )
                            }
                        }
                    }
                }
                state.studentData != null -> {
                    val data = state.studentData!!
                    val student = data.profile.student
                    item { DetailCard(student.fullName, "${student.studentCode} · ${data.profile.status}\nNgày sinh: ${student.dateOfBirth?.let(::formatDate) ?: "—"} · Giới tính: ${student.gender ?: "—"}") }
                    item {
                        if (data.profile.showContacts) {
                            Text("Điện thoại học sinh: ${student.studentPhone ?: "—"}")
                            data.profile.guardians.forEach { guardian ->
                                Text("${guardian.fullName} · ${relationshipText(guardian.relationship)} · ${guardian.phone ?: "—"}${if (guardian.isPrimaryContact) " · Liên hệ chính" else ""}\n${guardian.notes ?: ""}")
                                if (data.profile.canEditContacts) OutlinedButton(onClick = { contactForm = HomeroomForm(state.context, student.id, guardian = guardian, contactMode = "guardian") }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Sửa hoặc xóa · ${guardian.fullName}") }
                            }
                            if (data.profile.canEditContacts) {
                                OutlinedButton(onClick = { contactForm = HomeroomForm(state.context, student.id, initialPhone = student.studentPhone ?: "") }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Sửa điện thoại học sinh") }
                                OutlinedButton(enabled = data.profile.guardians.size < 6, onClick = { contactForm = HomeroomForm(state.context, student.id, contactMode = "guardian") }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Thêm người giám hộ · ${data.profile.guardians.size}/6") }
                            }
                        } else Text("Bạn không có quyền xem thông tin liên hệ.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    item { Text("Quá trình học", fontWeight = FontWeight.SemiBold) }
                    items(data.profile.enrollments) { row -> DetailCard("${row.classCode} · ${row.className}", "${formatDate(row.startDate)} → ${row.endDate?.let(::formatDate) ?: "Đang tiếp tục"}\n${if (row.current) "Hiện tại" else "Lịch sử"} · ${row.status}\n${row.transferReason ?: ""}") }
                    item {
                        DetailCard("Lịch sử điểm danh", "${formatDate(state.context.from)} → ${formatDate(state.context.to)} · ${data.history.days.size} buổi · ${data.history.corrections.size} lần điều chỉnh")
                        if (data.history.days.isEmpty()) Text("Chưa có buổi điểm danh nào trong khoảng này.")
                    }
                    val historyDays = data.history.days.asReversed()
                    itemsIndexed(historyDays, key = { _, row -> row.id }) { index, row ->
                        ListSegment(index, historyDays.size) {
                            HomeroomListRow(
                                title = HomeroomPresentation.dayTitle(row.date),
                                subtitle = listOfNotNull(row.record.rawObservedAt?.let(::attendanceClock), row.record.note?.takeIf { it.isNotBlank() }).joinToString(" · ").ifBlank { null },
                                chips = listOf(HomeroomPresentation.studentChip(row.record.effectiveStatus, row.record.rawObservedAt?.let(::attendanceClock))),
                            )
                        }
                    }
                    items(data.history.corrections.sortedByDescending { it.at }) { row -> DetailCard("Điều chỉnh ${formatDate(row.date)}", "${attendanceStatusText(row.previousStatus)} → ${attendanceStatusText(row.nextStatus)} · ${attendanceTimestamp(row.at)}${row.note?.takeIf { it.isNotBlank() }?.let { "\n$it" } ?: ""}") }
                }
            }
        }
    }
}

/** Tabs of the class detail; "Sổ đầu bài" lists lesson ratings written by subject teachers. */
internal enum class DetailTab(val label: String) { Daily("Điểm danh"), Roster("Danh sách lớp"), LessonLogs("Sổ đầu bài") }

@Composable private fun DetailCard(title: String, text: String) {
    Card(Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(text)
        }
    }
}

@Composable private fun HistoryDateButton(label: String, date: String, onDate: (String) -> Unit) {
    val context = LocalContext.current
    OutlinedButton(onClick = {
        val selected = LocalDate.parse(date)
        DatePickerDialog(context, { _, year, month, day -> onDate(LocalDate.of(year, month + 1, day).toString()) }, selected.year, selected.monthValue - 1, selected.dayOfMonth).show()
    }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("$label: ${formatDate(date)}") }
}

internal fun matchesStudent(student: StudentIdentity, search: String): Boolean {
    fun normalized(value: String): String = java.text.Normalizer.normalize(value.lowercase(Locale.ROOT).replace('đ', 'd'), java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
    val term = normalized(search.trim())
    return normalized(student.fullName).contains(term) || normalized(student.studentCode).contains(term)
}

private fun attendanceClock(milliseconds: Double): String = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.of("Asia/Ho_Chi_Minh")).format(Instant.ofEpochMilli(milliseconds.toLong()))

private fun attendanceTimestamp(milliseconds: Double): String = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm", Locale.forLanguageTag("vi-VN")).withZone(ZoneId.of("Asia/Ho_Chi_Minh")).format(Instant.ofEpochMilli(milliseconds.toLong()))

/**
 * GVCN view of one class day: whole class, absentees first and highlighted (icon + text, not colour only),
 * with a per-row "Vắng không phép" checkbox. No reason is required; Giám thị marks presence on Điểm danh.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.dailyAttendanceItems(
    state: HomeroomDetailState,
    data: ClassDetail,
    canWrite: Boolean,
    search: String,
    onOpenStudent: (String) -> Unit,
    onToggle: (DailyRow, Boolean) -> Unit,
) {
    val daily = data.daily
    val schoolDay = daily.schoolDay
    val notMarked = HomeroomPresentation.classNotMarked(daily.classSaved != null, daily.published)
    val rows = daily.rows.filter { matchesStudent(it.student, search) }
    val (absent, others) = HomeroomPresentation.splitAbsentFirst(rows, { it.day?.rawObservation }, { it.day?.effectiveStatus })
    val canCorrect = canWrite && daily.canCorrect && !daily.archived
    item(key = "daily-head") {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when {
                daily.rows.isEmpty() -> Text("Lớp không có học sinh vào ngày này.")
                notMarked -> HomeroomBanner(
                    HomeroomPresentation.notMarkedMessage(state.context.date, vietnamToday()),
                    if (schoolDay.isSchoolDay && !schoolDay.outsideYear) "Khi Giám thị lưu điểm danh, học sinh vắng sẽ hiện ở đầu danh sách để bạn đánh dấu vắng không phép." else "Đây không phải ngày học.",
                    HomeroomTone.Neutral,
                    Icons.Outlined.HourglassEmpty,
                )
                else -> {
                    if (schoolDay.outsideYear || !schoolDay.isSchoolDay) {
                        HomeroomBanner(if (schoolDay.outsideYear) "Ngoài năm học" else "Không phải ngày học", schoolDay.note.ifBlank { null }, HomeroomTone.Info, Icons.Outlined.EventBusy)
                    }
                    StatTiles(HomeroomPresentation.dailyStats(daily.rows.map { it.day?.effectiveStatus ?: "no_data" }))
                    daily.classSaved?.let { saved ->
                        Text(
                            "Giám thị lưu lúc ${attendanceClock(saved.savedAt)}${saved.savedByName.takeIf { it.isNotBlank() }?.let { " · $it" } ?: ""}",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
            if (daily.archived) Text("Lớp đã lưu trữ — chỉ xem.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            state.actionError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            state.actionMessage?.let { Text(it, color = toneColors(HomeroomTone.Success).text) }
            if (!notMarked && !canCorrect && !daily.archived && absent.isNotEmpty()) {
                Text("Chỉ GVCN của lớp (hoặc quản trị viên) mới đánh dấu được vắng không phép.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            }
            if (rows.isEmpty() && daily.rows.isNotEmpty()) Text("Không tìm thấy học sinh.")
        }
    }
    if (notMarked || daily.rows.isEmpty()) return
    item(key = "absent-heading") {
        Column {
            Text("Vắng (${absent.size})", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall)
            if (absent.isEmpty()) Text("Không có học sinh vắng.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    itemsIndexed(absent, key = { _, row -> "absent-${row.enrollmentId}" }) { index, row ->
        ListSegment(index, absent.size) {
            AbsentAttendanceRow(row, canCorrect, busy = state.busyDayId == row.day?.id, locked = state.busyDayId != null || state.refreshing, onOpen = { onOpenStudent(row.student.id) }, onToggle = { checked -> onToggle(row, checked) })
        }
    }
    item(key = "present-heading") {
        Text("Có mặt (${others.size})", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleSmall)
    }
    itemsIndexed(others, key = { _, row -> "other-${row.enrollmentId}" }) { index, row ->
        ListSegment(index, others.size) {
            HomeroomListRow(
                title = row.student.fullName,
                subtitle = row.day?.note,
                chips = listOf(HomeroomPresentation.studentChip(row.day?.effectiveStatus ?: "no_data", row.day?.rawObservedAt?.let(::attendanceClock))),
                leading = row.rosterNumber?.toString() ?: "—",
                onClick = { onOpenStudent(row.student.id) },
            )
        }
    }
}

@Composable
private fun AbsentAttendanceRow(row: DailyRow, canCorrect: Boolean, busy: Boolean, locked: Boolean, onOpen: () -> Unit, onToggle: (Boolean) -> Unit) {
    val day = row.day
    val status = day?.effectiveStatus ?: "no_data"
    val unexcused = day?.disposition == "unexcused"
    val tone = toneColors(if (unexcused) HomeroomTone.Danger else HomeroomTone.Warning)
    Column(
        Modifier
            .fillMaxWidth()
            .background(tone.background.copy(alpha = 0.55f)),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .clickable(onClick = onOpen)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Outlined.PersonOff, contentDescription = "Vắng", tint = tone.text, modifier = Modifier.size(20.dp))
            Column(Modifier.weight(1f)) {
                Text("${row.rosterNumber?.let { "$it. " } ?: ""}${row.student.fullName}", fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val detail = listOfNotNull(day?.reasonCode?.takeIf { it.isNotBlank() }, day?.note?.takeIf { it.isNotBlank() }).joinToString(" — ")
                if (detail.isNotBlank()) Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            StatusChip(HomeroomPresentation.studentChip(status, null))
        }
        if (canCorrect && day?.rawObservation == "absent") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .toggleable(value = unexcused, enabled = !locked, role = Role.Checkbox, onValueChange = onToggle)
                    .padding(start = 44.dp, end = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (busy) CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                else Checkbox(checked = unexcused, onCheckedChange = null, enabled = !locked)
                Text("Vắng không phép", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

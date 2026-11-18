package lvt.crm.ui.attendance

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.PersonOff
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.flow.drop
import lvt.crm.data.attendance.AttendanceClass
import lvt.crm.data.attendance.AttendancePresentation
import lvt.crm.data.attendance.AttendanceRoster
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.homeroom.DayNavigator
import lvt.crm.ui.homeroom.HomeroomBanner
import lvt.crm.ui.homeroom.HomeroomChip
import lvt.crm.ui.homeroom.HomeroomPresentation
import lvt.crm.ui.homeroom.HomeroomTone
import lvt.crm.ui.homeroom.StatusChip
import lvt.crm.ui.homeroom.formatDate
import lvt.crm.ui.homeroom.toneColors
import lvt.crm.ui.components.GuideAnchors

private const val UNSAVED_PROMPT = "Lớp đang mở có thay đổi chưa lưu. Bỏ các thay đổi này?"

/**
 * Điểm danh (Giám thị): chọn khối → mở lớp → tick "Vắng" → Lưu lớp. Mặc định cả lớp có mặt.
 * [onBack] shows a back arrow when the screen is opened from Lớp chủ nhiệm (not a bottom tab);
 * [onLeave] performs the system back once unsaved ticks were confirmed as discarded.
 */
@Composable
fun AttendanceScreen(
    viewModel: AttendanceViewModel,
    onBack: (() -> Unit)?,
    onLeave: () -> Unit,
) {
    val state by viewModel.uiState.collectAsState()
    val latestLeave by rememberUpdatedState(onLeave)
    LaunchedEffect(viewModel) {
        viewModel.leaveRequests.drop(1).collect { latestLeave() }
    }
    BackHandler(enabled = state.dirty || state.saving) {
        if (viewModel.requestLeave()) latestLeave()
    }
    if (state.pendingAction != null) {
        AlertDialog(
            onDismissRequest = viewModel::cancelDiscard,
            title = { Text("Bỏ thay đổi chưa lưu?") },
            text = { Text(UNSAVED_PROMPT) },
            confirmButton = {
                TextButton(onClick = viewModel::confirmDiscard) {
                    Text("Bỏ thay đổi", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::cancelDiscard) { Text("Ở lại") }
            },
        )
    }
    LvtScreen(
        title = "Điểm danh",
        helpAnchor = GuideAnchors.ATTENDANCE,
        refreshing = state.refreshing,
        onRefresh = viewModel::refresh,
        showAccountHeader = onBack == null,
        navigationIcon = onBack?.let { back ->
            {
                IconButton(onClick = { if (viewModel.requestLeave()) back() }) {
                    Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại")
                }
            }
        },
    ) {
        val roster = state.roster
        when {
            state.loading && roster == null -> Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator()
                Text("Đang tải danh sách lớp…", modifier = Modifier.padding(top = 12.dp))
            }
            state.error != null && roster == null -> StatePanel(
                icon = Icons.Outlined.WarningAmber,
                title = "Chưa tải được danh sách lớp",
                message = state.error.orEmpty(),
                action = { Button(onClick = viewModel::refresh) { Text("Thử lại") } },
            )
            roster != null -> AttendanceContent(state, roster, viewModel)
        }
    }
}

@Composable
private fun AttendanceContent(state: AttendanceUiState, roster: AttendanceRoster, viewModel: AttendanceViewModel) {
    val grade = roster.grade(state.grade)
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "head") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("GIÁM THỊ", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    listOfNotNull(
                        "${HomeroomPresentation.dayTitle(roster.date)}/${roster.date.take(4)}",
                        roster.schoolYear?.let { "Năm học ${it.name}" },
                    ).joinToString(" · "),
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium,
                )
                if (roster.canChooseDate) {
                    DayNavigator(date = roster.date, onDate = viewModel::selectDate)
                    if (roster.date != roster.today) {
                        OutlinedButton(onClick = { viewModel.selectDate(roster.today) }, modifier = Modifier.heightIn(min = 44.dp)) { Text("Về hôm nay") }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Outlined.Info, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp))
                    Text("Nhập bằng Excel: dùng bản web.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                }
                if (state.error != null) {
                    Text(state.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        if (roster.schoolYear == null) {
            item(key = "no-year") {
                HomeroomBanner(
                    "Ngày ${formatDate(roster.date)} không thuộc năm học nào.",
                    "Quản trị viên tạo năm học trong Thiết lập năm học trên bản web.",
                    HomeroomTone.Neutral,
                    Icons.Outlined.CalendarMonth,
                )
            }
            return@LazyColumn
        }
        if (!roster.schoolDay.isSchoolDay) {
            item(key = "not-school-day") {
                HomeroomBanner(
                    "${if (roster.schoolDay.outsideYear) "Ngoài năm học" else "Không phải ngày học"} — vẫn có thể lưu điểm danh nếu cần.",
                    roster.schoolDay.note.ifBlank { "Theo lịch, hôm nay không phải ngày học." },
                    HomeroomTone.Info,
                    Icons.Outlined.EventBusy,
                )
            }
        }
        item(key = "grades") {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AttendancePresentation.tabs(roster).forEach { level ->
                    val tab = roster.grade(level)
                    FilterChip(
                        selected = state.grade == level,
                        onClick = { viewModel.selectGrade(level) },
                        label = {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                                Text("Lớp $level", fontWeight = FontWeight.Bold, maxLines = 1)
                                Text("${tab.savedCount}/${tab.classes.size}", fontSize = 12.sp, maxLines = 1)
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 52.dp)
                            .semantics { contentDescription = "Lớp $level, đã lưu ${tab.savedCount} trên ${tab.classes.size} lớp" },
                    )
                }
            }
        }
        if (grade.classes.isEmpty()) {
            item(key = "empty-grade") {
                HomeroomBanner("Chưa có lớp khối ${state.grade} đang hoạt động.", null, HomeroomTone.Neutral, Icons.Outlined.CalendarMonth)
            }
        } else {
            items(grade.classes, key = { it.classId }) { klass ->
                ClassCard(
                    klass = klass,
                    open = state.openClassId == klass.classId,
                    state = state,
                    viewModel = viewModel,
                )
            }
        }
    }
}

@Composable
private fun ClassCard(klass: AttendanceClass, open: Boolean, state: AttendanceUiState, viewModel: AttendanceViewModel) {
    val statusChip = if (klass.saved != null) {
        HomeroomChip(AttendancePresentation.classStatusText(klass.saved), HomeroomTone.Success)
    } else {
        HomeroomChip(AttendancePresentation.classStatusText(null), HomeroomTone.Warning)
    }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .clickable(enabled = !state.saving, onClickLabel = if (open) "Thu gọn lớp" else "Mở lớp") { viewModel.toggleClass(klass.classId) }
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text("Lớp ${klass.name}", fontWeight = FontWeight.Bold)
                Text("Sĩ số ${klass.students.size}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            }
            Icon(
                if (klass.saved != null) Icons.Outlined.CheckCircle else Icons.Outlined.Schedule,
                contentDescription = null,
                tint = toneColors(statusChip.tone).text,
                modifier = Modifier.size(16.dp),
            )
            StatusChip(statusChip)
            Icon(if (open) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, contentDescription = null)
        }
        if (open) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))
            ClassEditor(klass, state, viewModel)
        }
    }
}

@Composable
private fun ClassEditor(klass: AttendanceClass, state: AttendanceUiState, viewModel: AttendanceViewModel) {
    if (klass.students.isEmpty()) {
        Text("Lớp chưa có học sinh vào ngày này.", modifier = Modifier.padding(14.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        return
    }
    val absent = state.draftAbsent
    val danger = toneColors(HomeroomTone.Danger)
    Column(Modifier.fillMaxWidth()) {
        klass.students.forEachIndexed { index, student ->
            val isAbsent = student.studentId in absent
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .background(if (isAbsent) danger.background else MaterialTheme.colorScheme.surfaceContainerLow)
                    .toggleable(
                        value = isAbsent,
                        enabled = !state.saving,
                        role = Role.Checkbox,
                        onValueChange = { viewModel.toggleAbsent(student.studentId) },
                    )
                    .semantics { stateDescription = if (isAbsent) "Vắng" else "Có mặt" }
                    .padding(start = 14.dp, end = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "${student.rosterNumber ?: index + 1}.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontSize = 13.sp,
                    modifier = Modifier.widthIn(min = 24.dp),
                )
                Text(student.fullName, modifier = Modifier.weight(1f), fontWeight = if (isAbsent) FontWeight.Bold else FontWeight.Normal)
                if (isAbsent) Icon(Icons.Outlined.PersonOff, contentDescription = null, tint = danger.text, modifier = Modifier.size(18.dp))
                Text("Vắng", color = if (isAbsent) danger.text else MaterialTheme.colorScheme.onSurfaceVariant, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Checkbox(checked = isAbsent, onCheckedChange = null)
            }
            if (index < klass.students.lastIndex) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
        }
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                AttendancePresentation.countSummary(klass.students.size, absent.size) + if (state.dirty) " · chưa lưu" else "",
                fontWeight = FontWeight.SemiBold,
            )
            state.saveError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            state.saveMessage?.let { Text(it, color = toneColors(HomeroomTone.Success).text) }
            Button(
                onClick = viewModel::saveOpenClass,
                enabled = !state.saving,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                colors = ButtonDefaults.buttonColors(),
            ) {
                if (state.saving) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    Text("  ")
                }
                Text(AttendancePresentation.saveButtonLabel(klass.name, absent.size, state.saving))
            }
        }
    }
}

package lvt.crm.ui.boarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.EventNote
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import lvt.crm.data.boarding.BoardingAdminData
import lvt.crm.data.boarding.BoardingAdminPeriod
import lvt.crm.data.boarding.BoardingPerson
import lvt.crm.data.boarding.BoardingReport
import lvt.crm.data.boarding.BoardingRules
import lvt.crm.ui.components.GuideAnchors
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.components.StatusPill
import lvt.crm.ui.components.StatusTone

/**
 * Bán trú, opened from Tổng quan. Admin/mod get "Kỳ bán trú" (periods) and
 * "Danh sách tham gia"; everyone else with Báo cáo access only the list (web BoardingPage).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BoardingScreen(viewModel: BoardingViewModel, onBack: () -> Unit) {
    val state by viewModel.uiState.collectAsState()
    BackHandler(enabled = state.editor != null) { viewModel.closeEditor() }
    LvtScreen(
        title = "Bán trú",
        refreshing = state.refreshing,
        onRefresh = viewModel::refresh,
        helpAnchor = GuideAnchors.BOARDING,
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại")
            }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            if (state.canManage) {
                PrimaryTabRow(selectedTabIndex = state.visibleTab.ordinal) {
                    BoardingTab.entries.forEach { tab ->
                        Tab(
                            selected = state.visibleTab == tab,
                            onClick = { viewModel.selectTab(tab) },
                            text = { Text(tab.title) },
                        )
                    }
                }
            }
            state.notice?.let { message ->
                Text(
                    message,
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
            when (state.visibleTab) {
                BoardingTab.Participants -> ParticipantsTab(state, viewModel)
                BoardingTab.Periods -> PeriodsTab(state, viewModel)
            }
        }
    }

    state.pendingDelete?.let { period ->
        AlertDialog(
            onDismissRequest = viewModel::dismissDelete,
            title = { Text("Xóa ${BoardingRules.periodLabel(period.period)}?") },
            text = { Text("Kỳ bán trú và danh sách giáo viên tham gia sẽ không còn hiển thị.") },
            confirmButton = {
                TextButton(onClick = viewModel::confirmDelete) { Text("Xóa") }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissDelete) { Text("Hủy") }
            },
        )
    }
}

@Composable
private fun LoadingPanel(message: String) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator()
        Text(message, modifier = Modifier.padding(top = 14.dp))
    }
}

@Composable
private fun ParticipantsTab(state: BoardingUiState, viewModel: BoardingViewModel) {
    val report = state.report
    when {
        report == null && state.reportLoading -> LoadingPanel("Đang tải các kỳ bán trú…")
        report == null -> StatePanel(
            icon = Icons.Outlined.WarningAmber,
            title = "Chưa tải được danh sách",
            message = state.reportError.orEmpty(),
            action = { Button(onClick = viewModel::refresh) { Text("Thử lại") } },
        )
        else -> ParticipantsList(report, state, viewModel)
    }
}

@Composable
private fun ParticipantsList(report: BoardingReport, state: BoardingUiState, viewModel: BoardingViewModel) {
    var pickingPeriod by remember { mutableStateOf(false) }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "picker") {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("CHỌN KỲ CẦN XEM", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    Text(BoardingRules.periodLabel(report.selectedPeriod), style = MaterialTheme.typography.titleMedium)
                    Text(
                        if (report.isSchoolWide) {
                            "Bạn đang xem toàn bộ phòng ban tham gia bán trú."
                        } else {
                            "Bạn đang xem giáo viên tham gia bán trú trong phòng ban của mình."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedButton(
                        onClick = { pickingPeriod = true },
                        enabled = report.periods.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (report.periods.isEmpty()) "Chưa có kỳ bán trú" else "Đổi kỳ bán trú")
                    }
                    if (report.periods.isNotEmpty() && !BoardingRules.hasPeriodForYear(report.periods, state.currentSchoolYear)) {
                        Text(
                            "Chưa có kỳ bán trú cho năm học ${state.currentSchoolYear}.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
        state.reportError?.let { message ->
            item(key = "error") {
                Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
        val selected = report.selectedPeriod
        if (selected == null) {
            item(key = "empty-period") {
                StatePanel(
                    icon = Icons.Outlined.EventNote,
                    title = "Chưa có kỳ bán trú để xem",
                    message = "Quản trị viên cần tạo kỳ bán trú và thêm giáo viên tham gia trước.",
                )
            }
        } else {
            item(key = "stats") {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatCard("${report.totalParticipants}", "Giáo viên tham gia", Modifier.weight(1f))
                    StatCard("${report.groups.size}", "Phòng ban", Modifier.weight(1f))
                }
            }
            if (report.groups.isEmpty()) {
                item(key = "empty-group") {
                    StatePanel(
                        icon = Icons.Outlined.Groups,
                        title = "Chưa có giáo viên tham gia trong kỳ này",
                        message = "Hãy chọn kỳ khác. Quản trị viên cập nhật danh sách ở menu Bán trú › Kỳ bán trú.",
                    )
                }
            }
            items(report.groups, key = { "group-${it.departmentName}" }) { group ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text("PHÒNG BAN", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                                Text(group.departmentName, style = MaterialTheme.typography.titleMedium)
                            }
                            Text("${group.participants.size} giáo viên", style = MaterialTheme.typography.labelLarge)
                        }
                        group.participants.forEachIndexed { index, person ->
                            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    (index + 1).toString().padStart(2, '0'),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.width(28.dp),
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(person.name, style = MaterialTheme.typography.bodyLarge)
                                    Text(
                                        listOf(person.positionName, person.email).filter { it.isNotBlank() }.joinToString(" · "),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                StatusPill(label = "Đã đăng ký", tone = StatusTone.Positive)
                            }
                        }
                    }
                }
            }
            item(key = "footnote") {
                Text(
                    "Danh sách do quản trị viên thiết lập trong menu Bán trú.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
    if (pickingPeriod) {
        ChoiceDialog(
            title = "Kỳ bán trú",
            items = report.periods.map { it.id to BoardingRules.periodLabel(it) },
            selectedId = report.selectedPeriod?.id,
            onSelect = { id ->
                pickingPeriod = false
                viewModel.selectPeriod(id)
            },
            onDismiss = { pickingPeriod = false },
        )
    }
}

@Composable
private fun StatCard(value: String, label: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = .5f)),
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(value, style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary)
            Text(label, style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun PeriodsTab(state: BoardingUiState, viewModel: BoardingViewModel) {
    val admin = state.admin
    when {
        admin == null && state.adminLoading -> LoadingPanel("Đang tải dữ liệu bán trú…")
        admin == null -> StatePanel(
            icon = Icons.Outlined.WarningAmber,
            title = "Chưa tải được kỳ bán trú",
            message = state.adminError.orEmpty(),
            action = { Button(onClick = viewModel::refresh) { Text("Thử lại") } },
        )
        state.editor != null -> PeriodEditor(state, admin, viewModel)
        else -> PeriodList(state, admin, viewModel)
    }
}

@Composable
private fun PeriodList(state: BoardingUiState, admin: BoardingAdminData, viewModel: BoardingViewModel) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "add") {
            Button(onClick = viewModel::startCreate, enabled = !state.saving, modifier = Modifier.fillMaxWidth()) {
                Text("＋ Thêm kỳ bán trú")
            }
        }
        state.actionError?.let { message ->
            item(key = "error") {
                Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
        item(key = "heading") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Các kỳ bán trú đã thiết lập", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                Text("${admin.periods.size}", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.primary)
            }
        }
        if (admin.periods.isEmpty()) {
            item(key = "empty") {
                StatePanel(
                    icon = Icons.Outlined.EventNote,
                    title = "Chưa có kỳ bán trú",
                    message = "Tạo kỳ đầu tiên để bắt đầu phân công giáo viên.",
                )
            }
        } else if (!BoardingRules.hasPeriodForYear(admin.periods.map { it.period }, state.currentSchoolYear)) {
            item(key = "no-current") {
                Text(
                    "Chưa có kỳ bán trú cho năm học ${state.currentSchoolYear}.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(admin.periods, key = { "period-${it.period.id}" }) { period ->
            PeriodCard(period, busy = state.saving, onEdit = { viewModel.startEdit(period) }, onDelete = { viewModel.requestDelete(period) })
        }
    }
}

@Composable
private fun PeriodCard(period: BoardingAdminPeriod, busy: Boolean, onEdit: () -> Unit, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            StatusPill(label = BoardingRules.periodLabel(period.period, short = true), tone = StatusTone.Primary)
            Text("Năm học", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(period.period.schoolYear, style = MaterialTheme.typography.titleLarge)
            Text("${period.participants.size} giáo viên tham gia", style = MaterialTheme.typography.labelLarge)
            if (period.participants.isNotEmpty()) {
                Text(
                    period.participants.joinToString(", ") { it.name },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onEdit, enabled = !busy) { Text("Sửa") }
                OutlinedButton(
                    onClick = onDelete,
                    enabled = !busy,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Xóa") }
            }
        }
    }
}

@Composable
private fun PeriodEditor(state: BoardingUiState, admin: BoardingAdminData, viewModel: BoardingViewModel) {
    val editor = state.editor ?: return
    var pickingYear by remember { mutableStateOf(false) }
    var pickingTeachers by remember { mutableStateOf(false) }
    val selectedUsers = editor.participantUserIds.mapNotNull { id -> admin.users.firstOrNull { it.id == id } }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    if (editor.editingId != null) "Chỉnh sửa thiết lập" else "Thiết lập kỳ mới",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    if (editor.editingId != null) "Sửa kỳ bán trú" else "Thêm kỳ bán trú",
                    style = MaterialTheme.typography.titleLarge,
                )
            }
            IconButton(onClick = viewModel::closeEditor) {
                Icon(Icons.Outlined.Close, contentDescription = "Đóng biểu mẫu")
            }
        }
        Text("Học kỳ", style = MaterialTheme.typography.titleSmall)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(1, 2).forEach { semester ->
                FilterChip(
                    selected = editor.semester == semester,
                    onClick = { viewModel.updateEditor { it.copy(semester = semester) } },
                    label = {
                        Column(modifier = Modifier.padding(vertical = 6.dp)) {
                            Text("Học kỳ $semester")
                            Text(
                                if (semester == 1) "Nửa đầu năm học" else "Nửa sau năm học",
                                style = MaterialTheme.typography.labelSmall,
                            )
                        }
                    },
                )
            }
        }
        Text("Năm học", style = MaterialTheme.typography.titleSmall)
        OutlinedButton(onClick = { pickingYear = true }, modifier = Modifier.fillMaxWidth()) {
            Text(editor.schoolYear)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Giáo viên tham gia (${selectedUsers.size})", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            TextButton(onClick = { pickingTeachers = true }) { Text("＋ Thêm giáo viên") }
        }
        if (selectedUsers.isEmpty()) {
            Text(
                "Chưa có giáo viên tham gia. Nhấn “Thêm giáo viên” để chọn từ danh sách.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        selectedUsers.forEach { user ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(user.name, style = MaterialTheme.typography.bodyLarge)
                    Text(teacherSubtitle(user), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = {
                    viewModel.updateEditor { it.copy(participantUserIds = it.participantUserIds - user.id) }
                }) {
                    Icon(Icons.Outlined.Close, contentDescription = "Bỏ chọn ${user.name}")
                }
            }
        }
        state.actionError?.let { message ->
            Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = viewModel::closeEditor, enabled = !state.saving, modifier = Modifier.weight(1f)) { Text("Hủy") }
            Button(onClick = viewModel::save, enabled = !state.saving, modifier = Modifier.weight(1f)) {
                Text(
                    when {
                        state.saving -> "Đang lưu…"
                        editor.editingId != null -> "Lưu thay đổi"
                        else -> "Tạo kỳ bán trú"
                    },
                )
            }
        }
        Spacer(Modifier.padding(bottom = 16.dp))
    }
    if (pickingYear) {
        val years = BoardingRules.schoolYearOptions(include = editor.schoolYear)
        ChoiceDialog(
            title = "Năm học",
            items = years.map { it to it },
            selectedId = editor.schoolYear,
            onSelect = { year ->
                pickingYear = false
                viewModel.updateEditor { it.copy(schoolYear = year) }
            },
            onDismiss = { pickingYear = false },
        )
    }
    if (pickingTeachers) {
        TeacherPickerDialog(
            users = admin.users,
            selectedIds = editor.participantUserIds,
            onDismiss = { pickingTeachers = false },
            onComplete = { ids ->
                pickingTeachers = false
                viewModel.updateEditor { it.copy(participantUserIds = ids) }
            },
        )
    }
}

private fun teacherSubtitle(user: BoardingPerson): String =
    user.positionName.ifBlank { "Chưa gán chức vụ" } +
        (if (user.departmentName.isNotBlank()) " · ${user.departmentName}" else "")

@Composable
private fun TeacherPickerDialog(
    users: List<BoardingPerson>,
    selectedIds: List<String>,
    onDismiss: () -> Unit,
    onComplete: (List<String>) -> Unit,
) {
    var draft by remember { mutableStateOf(selectedIds) }
    var search by remember { mutableStateOf("") }
    val query = search.trim().lowercase()
    val filtered = users.filter { user ->
        query.isEmpty() ||
            "${user.name} ${user.email} ${user.departmentName} ${user.positionName}".lowercase().contains(query)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Chọn giáo viên tham gia") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = search,
                    onValueChange = { search = it },
                    placeholder = { Text("Tìm theo tên, email, phòng ban…") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row {
                    TextButton(onClick = { draft = users.map { it.id } }) { Text("Chọn tất cả") }
                    TextButton(onClick = { draft = emptyList() }) { Text("Bỏ chọn") }
                }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 320.dp)
                        .verticalScroll(rememberScrollState()),
                ) {
                    if (filtered.isEmpty()) Text("Không tìm thấy giáo viên phù hợp.")
                    filtered.forEach { user ->
                        val checked = user.id in draft
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { draft = if (checked) draft - user.id else draft + user.id },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(
                                checked = checked,
                                onCheckedChange = { draft = if (checked) draft - user.id else draft + user.id },
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(user.name, style = MaterialTheme.typography.bodyLarge)
                                Text(teacherSubtitle(user), style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
                Text("${draft.size} giáo viên đã chọn", style = MaterialTheme.typography.labelMedium)
            }
        },
        confirmButton = { Button(onClick = { onComplete(draft) }) { Text("Hoàn thành") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Hủy") } },
    )
}

@Composable
private fun ChoiceDialog(
    title: String,
    items: List<Pair<String, String>>,
    selectedId: String?,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 360.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                items.forEach { (id, label) ->
                    TextButton(onClick = { onSelect(id) }, modifier = Modifier.fillMaxWidth()) {
                        Text(if (id == selectedId) "✓ $label" else label)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Đóng") } },
    )
}

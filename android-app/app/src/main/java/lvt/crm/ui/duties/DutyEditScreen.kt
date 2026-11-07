package lvt.crm.ui.duties

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.duties.DutiesRepository
import lvt.crm.data.duties.DutyFormOption
import lvt.crm.data.duties.DutyFormOptions
import lvt.crm.data.duties.SharedDutyEvent
import lvt.crm.ui.components.LvtScreen
import java.time.LocalDate

private enum class PickTarget { Departments, Users }

/** Văn thư edits one duty of the shared sheet. Saving sends the week back for BGH approval. */
@Composable
fun DutyEditScreen(
    dutiesRepository: DutiesRepository,
    event: SharedDutyEvent,
    onClose: () -> Unit,
    onSaved: () -> Unit,
) {
    val context = LocalContext.current
    var draft by remember(event.id) { mutableStateOf(DutyEditRules.draftFrom(event)) }
    var options by remember { mutableStateOf<DutyFormOptions?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var confirmSave by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf<PickTarget?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        runCatching { dutiesRepository.formOptions() }
            .onSuccess { options = it }
            .onFailure { error = (it as? ConvexException)?.message ?: "Không tải được danh sách phòng ban, người dùng." }
    }

    fun pickDate(current: String, onPicked: (String) -> Unit) {
        val date = runCatching { LocalDate.parse(current) }.getOrElse { LocalDate.now() }
        DatePickerDialog(context, { _, year, month, day ->
            onPicked(LocalDate.of(year, month + 1, day).toString())
        }, date.year, date.monthValue - 1, date.dayOfMonth).show()
    }

    fun pickTime(current: String, onPicked: (String) -> Unit) {
        val parts = current.split(":").mapNotNull { it.toIntOrNull() }
        TimePickerDialog(context, { _, hour, minute ->
            onPicked("%02d:%02d".format(hour, minute))
        }, parts.getOrElse(0) { 7 }, parts.getOrElse(1) { 0 }, true).show()
    }

    BackHandler(enabled = !saving, onBack = onClose)
    LvtScreen(
        title = "Sửa công tác",
        navigationIcon = {
            IconButton(onClick = onClose, enabled = !saving) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Đóng") }
        },
    ) {
        val loaded = options
        if (loaded == null) {
            Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                if (error == null) CircularProgressIndicator() else Text(error.orEmpty(), color = MaterialTheme.colorScheme.error)
            }
            return@LvtScreen
        }
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            OutlinedTextField(
                value = draft.title,
                onValueChange = { draft = draft.copy(title = it.take(DutyEditRules.TEXT_MAX)) },
                label = { Text("Tên công tác") },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = draft.content,
                onValueChange = { draft = draft.copy(content = it.take(DutyEditRules.TEXT_MAX)) },
                label = { Text("Nội dung") },
                minLines = 2,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Cả ngày", modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                Switch(checked = draft.allDay, onCheckedChange = { draft = draft.copy(allDay = it) })
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { pickDate(draft.startDate) { draft = draft.copy(startDate = it, endDate = maxOf(it, draft.endDate)) } }, modifier = Modifier.weight(1f)) {
                    Text("Từ ${DutyEditRules.dateLabel(draft.startDate)}")
                }
                if (!draft.allDay) {
                    OutlinedButton(onClick = { pickTime(draft.startTime) { draft = draft.copy(startTime = it) } }) {
                        Text(SharedWeekPresentation.clock(draft.startTime))
                    }
                }
            }
            if (!draft.allDay) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { pickDate(draft.endDate) { draft = draft.copy(endDate = it) } }, modifier = Modifier.weight(1f)) {
                        Text("Đến ${DutyEditRules.dateLabel(draft.endDate)}")
                    }
                    OutlinedButton(onClick = { pickTime(draft.endTime) { draft = draft.copy(endTime = it) } }) {
                        Text(SharedWeekPresentation.clock(draft.endTime))
                    }
                }
            }
            OutlinedTextField(
                value = draft.locationText,
                onValueChange = { draft = draft.copy(locationText = it.take(DutyEditRules.TEXT_MAX)) },
                label = { Text("Địa điểm") },
                modifier = Modifier.fillMaxWidth(),
            )
            Text("Thành phần", style = MaterialTheme.typography.titleSmall)
            if (loaded.isOps) {
                OutlinedButton(onClick = { picking = PickTarget.Departments }, modifier = Modifier.fillMaxWidth()) {
                    Text(selectionLabel("Phòng ban", draft.departmentIds, loaded.departments))
                }
            }
            OutlinedButton(onClick = { picking = PickTarget.Users }, modifier = Modifier.fillMaxWidth()) {
                Text(selectionLabel("Cá nhân", draft.participantUserIds, loaded.users))
            }
            OutlinedTextField(
                value = draft.otherParticipants,
                onValueChange = { draft = draft.copy(otherParticipants = it.take(DutyEditRules.OTHER_MAX)) },
                label = { Text("Thành phần khác") },
                placeholder = { Text("Đoàn công tác, khách mời…") },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                "Lưu xong, thay đổi chờ Ban Giám hiệu duyệt. Giáo viên vẫn thấy bản đã duyệt trước đó.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Button(
                onClick = {
                    error = DutyEditRules.error(draft)
                    if (error == null) confirmSave = true
                },
                enabled = !saving,
                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
            ) { Text(if (saving) "Đang lưu…" else "Lưu thay đổi") }
        }
    }

    if (confirmSave) {
        AlertDialog(
            onDismissRequest = { if (!saving) confirmSave = false },
            title = { Text("Lưu thay đổi?") },
            text = { Text("Lịch tuần sẽ cần Ban Giám hiệu duyệt lại.") },
            confirmButton = {
                Button(enabled = !saving, onClick = {
                    saving = true
                    scope.launch {
                        runCatching { dutiesRepository.updateDuty(DutyEditRules.trimmed(draft)) }
                            .onSuccess {
                                confirmSave = false
                                saving = false
                                onSaved()
                            }
                            .onFailure {
                                error = (it as? ConvexException)?.message ?: "Không lưu được. Hãy thử lại."
                                confirmSave = false
                                saving = false
                            }
                    }
                }) { Text(if (saving) "Đang lưu…" else "Lưu") }
            },
            dismissButton = { TextButton(onClick = { confirmSave = false }, enabled = !saving) { Text("Hủy") } },
        )
    }

    val target = picking
    val loaded = options
    if (target != null && loaded != null) {
        MultiSelectDialog(
            title = if (target == PickTarget.Departments) "Chọn phòng ban" else "Chọn cá nhân",
            options = if (target == PickTarget.Departments) loaded.departments else loaded.users,
            selected = if (target == PickTarget.Departments) draft.departmentIds else draft.participantUserIds,
            onDismiss = { picking = null },
            onConfirm = { ids ->
                draft = if (target == PickTarget.Departments) draft.copy(departmentIds = ids) else draft.copy(participantUserIds = ids)
                picking = null
            },
        )
    }
}

private fun selectionLabel(kind: String, ids: List<String>, options: List<DutyFormOption>): String {
    if (ids.isEmpty()) return "$kind: chưa chọn"
    val names = options.filter { it.id in ids }.map { it.label }
    return if (names.size <= 2) "$kind: ${names.joinToString(", ")}" else "$kind: ${names.take(2).joinToString(", ")} +${names.size - 2}"
}

@Composable
private fun MultiSelectDialog(
    title: String,
    options: List<DutyFormOption>,
    selected: List<String>,
    onDismiss: () -> Unit,
    onConfirm: (List<String>) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    var chosen by remember { mutableStateOf(selected.toSet()) }
    val visible = options.filter {
        query.isBlank() || it.label.contains(query.trim(), ignoreCase = true) || it.detail.contains(query.trim(), ignoreCase = true)
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    placeholder = { Text("Tìm…") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                LazyColumn(Modifier.heightIn(max = 360.dp)) {
                    items(visible, key = { it.id }) { option ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable { chosen = if (option.id in chosen) chosen - option.id else chosen + option.id }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(checked = option.id in chosen, onCheckedChange = null)
                            Column(Modifier.padding(start = 8.dp)) {
                                Text(option.label)
                                if (option.detail.isNotBlank()) {
                                    Text(option.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { Button(onClick = { onConfirm(options.map { it.id }.filter { it in chosen }) }) { Text("Xong (${chosen.size})") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Hủy") } },
    )
}

package lvt.crm.ui.todos

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ChecklistRtl
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import lvt.crm.data.todos.PersonalTodo
import lvt.crm.data.todos.PersonalTodoRules
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.homeroom.HomeroomChip
import lvt.crm.ui.homeroom.HomeroomTone
import lvt.crm.ui.homeroom.StatusChip
import lvt.crm.ui.homeroom.toneColors
import lvt.crm.ui.components.GuideAnchors

/** "Việc của tôi": private to-dos, visible only to their owner. */
@Composable
fun PersonalTodosScreen(viewModel: PersonalTodosViewModel) {
    val state by viewModel.uiState.collectAsState()
    val listState = rememberLazyListState()
    state.draft?.let { TodoFormDialog(it, viewModel) }
    state.confirmDelete?.let { todo ->
        AlertDialog(
            onDismissRequest = viewModel::cancelDelete,
            title = { Text("Xóa việc “${todo.title}”?") },
            text = { Text("Việc sẽ biến mất khỏi danh sách và không còn nhắc.") },
            confirmButton = {
                TextButton(onClick = viewModel::confirmDelete, enabled = state.busyId == null) {
                    Text(if (state.busyId == todo.id) "Đang xóa…" else "Xóa", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = viewModel::cancelDelete, enabled = state.busyId == null) { Text("Hủy") } },
        )
    }
    val list = state.list
    LaunchedEffect(state.focusId, list) {
        val focus = state.focusId ?: return@LaunchedEffect
        val current = list ?: return@LaunchedEffect
        val openIndex = current.open.indexOfFirst { it.id == focus }
        val doneIndex = current.completed.indexOfFirst { it.id == focus }
        // Header items: intro + open heading (+ open rows + completed heading).
        val index = when {
            openIndex >= 0 -> 2 + openIndex
            doneIndex >= 0 -> 3 + current.open.size.coerceAtLeast(1) + doneIndex
            else -> -1
        }
        if (index >= 0) listState.animateScrollToItem(index)
    }
    LvtScreen(
        title = "Việc của tôi",
        helpAnchor = GuideAnchors.WORK,
        refreshing = state.refreshing,
        onRefresh = viewModel::refresh,
        showAccountHeader = true,
    ) {
        when {
            state.loading && list == null -> Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator()
                Text("Đang tải danh sách việc…", modifier = Modifier.padding(top = 12.dp))
            }
            state.error != null && list == null -> StatePanel(
                icon = Icons.Outlined.WarningAmber,
                title = "Không tải được danh sách việc",
                message = state.error.orEmpty(),
                action = { Button(onClick = viewModel::refresh) { Text("Thử lại") } },
            )
            list != null -> LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                item(key = "intro") {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            "Danh sách việc riêng của bạn. Chỉ bạn nhìn thấy, không cần duyệt và không liên quan đến công văn.",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Button(onClick = viewModel::startCreate, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                            Icon(Icons.Outlined.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                            Text("  Thêm việc")
                        }
                        state.message?.let { Text(it, color = toneColors(HomeroomTone.Success).text) }
                        state.actionError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                    }
                }
                item(key = "open-heading") {
                    Column {
                        Text("Cần làm (${list.open.size})", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
                        if (list.open.isEmpty()) {
                            StatePanel(
                                icon = Icons.Outlined.ChecklistRtl,
                                title = "Chưa có việc cần làm",
                                message = "Bấm “Thêm việc” để ghi lại việc của bạn.",
                            )
                        }
                    }
                }
                items(list.open, key = { "open-${it.id}" }) { todo -> TodoRow(todo, state, viewModel) }
                if (list.completed.isNotEmpty()) {
                    item(key = "done-heading") {
                        Text("Đã hoàn thành gần đây (${list.completed.size})", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
                    }
                    items(list.completed, key = { "done-${it.id}" }) { todo -> TodoRow(todo, state, viewModel) }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TodoRow(todo: PersonalTodo, state: PersonalTodosUiState, viewModel: PersonalTodosViewModel) {
    val busy = state.busyId == todo.id
    val overdue = PersonalTodoRules.isOverdue(todo, System.currentTimeMillis())
    val focused = state.focusId == todo.id
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) MaterialTheme.colorScheme.secondaryContainer else MaterialTheme.colorScheme.surfaceContainerLow)
            .padding(vertical = 6.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .toggleable(
                    value = todo.done,
                    enabled = state.busyId == null,
                    role = Role.Checkbox,
                    onValueChange = { viewModel.setCompleted(todo, it) },
                )
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (busy) {
                CircularProgressIndicator(modifier = Modifier.padding(12.dp).size(20.dp), strokeWidth = 2.dp)
            } else {
                Checkbox(checked = todo.done, onCheckedChange = null, modifier = Modifier.padding(12.dp))
            }
            Text(
                todo.title,
                fontWeight = FontWeight.Bold,
                textDecoration = if (todo.done) TextDecoration.LineThrough else null,
                modifier = Modifier.weight(1f),
            )
        }
        Column(Modifier.padding(start = 56.dp, end = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (todo.note.isNotBlank()) Text(todo.note, style = MaterialTheme.typography.bodyMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                when {
                    todo.done -> StatusChip(HomeroomChip("Hoàn thành", HomeroomTone.Success))
                    overdue -> StatusChip(HomeroomChip("Quá hạn", HomeroomTone.Danger))
                }
                Meta(todo.dueAt?.let { "Hạn chót ${PersonalTodoRules.formatMoment(it)}" } ?: "Không có hạn chót")
                todo.remindAt?.let { Meta("Nhắc lúc ${PersonalTodoRules.formatMoment(it)}") }
                todo.completedAt?.let { Meta("Xong lúc ${PersonalTodoRules.formatMoment(it)}") }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (!todo.done) {
                    TextButton(onClick = { viewModel.startEdit(todo) }, enabled = state.busyId == null, modifier = Modifier.heightIn(min = 44.dp)) { Text("Sửa") }
                }
                TextButton(onClick = { viewModel.requestDelete(todo) }, enabled = state.busyId == null, modifier = Modifier.heightIn(min = 44.dp)) {
                    Text("Xóa", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

@Composable
private fun Meta(text: String) {
    Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun TodoFormDialog(draft: TodoDraft, viewModel: PersonalTodosViewModel) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = { if (!draft.saving) viewModel.cancelDraft() },
        title = { Text(if (draft.editingId != null) "Sửa việc" else "Thêm việc mới") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                draft.serverError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Column {
                    Text("Tên việc *", style = MaterialTheme.typography.labelLarge)
                    OutlinedTextField(
                        value = draft.title,
                        onValueChange = { viewModel.setTitle(it.take(PersonalTodoRules.TITLE_MAX)) },
                        singleLine = true,
                        enabled = !draft.saving,
                        isError = draft.errors["title"] != null,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    FieldError(draft.errors["title"])
                }
                Column {
                    Text("Ghi chú", style = MaterialTheme.typography.labelLarge)
                    OutlinedTextField(
                        value = draft.note,
                        onValueChange = { viewModel.setNote(it.take(PersonalTodoRules.NOTE_MAX)) },
                        minLines = 2,
                        enabled = !draft.saving,
                        isError = draft.errors["note"] != null,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    FieldError(draft.errors["note"])
                }
                MomentField(
                    label = "Hạn chót",
                    value = draft.dueAt,
                    enabled = !draft.saving,
                    error = draft.errors["due"],
                    help = null,
                    onPick = { pickMoment(context, draft.dueAt, viewModel::setDueAt) },
                    onClear = { viewModel.setDueAt(null) },
                )
                MomentField(
                    label = "Nhắc lúc",
                    value = draft.remindAt,
                    enabled = !draft.saving,
                    error = draft.errors["remind"],
                    help = "Gửi thông báo tới bạn vào giờ này.",
                    onPick = { pickMoment(context, draft.remindAt, viewModel::setRemindAt) },
                    onClear = { viewModel.setRemindAt(null) },
                )
            }
        },
        confirmButton = {
            Button(onClick = viewModel::saveDraft, enabled = !draft.saving) {
                Text(if (draft.saving) "Đang lưu…" else if (draft.editingId != null) "Lưu" else "Thêm việc")
            }
        },
        dismissButton = {
            TextButton(onClick = viewModel::cancelDraft, enabled = !draft.saving) { Text("Hủy") }
        },
    )
}

@Composable
private fun FieldError(error: String?) {
    if (error != null) Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
}

@Composable
private fun MomentField(label: String, value: Long?, enabled: Boolean, error: String?, help: String?, onPick: () -> Unit, onClear: () -> Unit) {
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onPick, enabled = enabled, modifier = Modifier.weight(1f).heightIn(min = 44.dp)) {
                Text(value?.let { PersonalTodoRules.formatMoment(it) } ?: "Chọn ngày giờ")
            }
            if (value != null) {
                TextButton(onClick = onClear, enabled = enabled, modifier = Modifier.heightIn(min = 44.dp)) { Text("Bỏ") }
            }
        }
        if (error != null) FieldError(error) else if (help != null) Text(help, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
    }
}

/** Date then time picker, read as Vietnam wall-clock time (UTC+7). */
private fun pickMoment(context: Context, current: Long?, onPicked: (Long) -> Unit) {
    val initial = PersonalTodoRules.vietnamDateTime(current ?: (System.currentTimeMillis() + 60 * 60 * 1000))
    DatePickerDialog(
        context,
        { _, year, month, day ->
            TimePickerDialog(
                context,
                { _, hour, minute -> onPicked(PersonalTodoRules.vietnamMillis(year, month + 1, day, hour, minute)) },
                initial.hour,
                initial.minute,
                true,
            ).show()
        },
        initial.year,
        initial.monthValue - 1,
        initial.dayOfMonth,
    ).show()
}

package lvt.crm.ui.todos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.todos.PersonalTodo
import lvt.crm.data.todos.PersonalTodoList
import lvt.crm.data.todos.PersonalTodoOperations
import lvt.crm.data.todos.PersonalTodoRules
import org.json.JSONException

/** Draft of the add/edit form. [editingId] null = new todo. */
data class TodoDraft(
    val editingId: String? = null,
    val title: String = "",
    val note: String = "",
    val dueAt: Long? = null,
    val remindAt: Long? = null,
    val previousRemindAt: Long? = null,
    val errors: Map<String, String> = emptyMap(),
    val serverError: String? = null,
    val saving: Boolean = false,
)

data class PersonalTodosUiState(
    val loading: Boolean = true,
    val refreshing: Boolean = false,
    val error: String? = null,
    val list: PersonalTodoList? = null,
    val draft: TodoDraft? = null,
    val busyId: String? = null,
    val confirmDelete: PersonalTodo? = null,
    val message: String? = null,
    val actionError: String? = null,
    /** Todo id from a reminder notification, highlighted in the list. */
    val focusId: String? = null,
)

class PersonalTodosViewModel(
    private val repository: PersonalTodoOperations,
    private val clock: () -> Long = System::currentTimeMillis,
) : ViewModel() {
    private val state = MutableStateFlow(PersonalTodosUiState())
    val uiState: StateFlow<PersonalTodosUiState> = state.asStateFlow()
    private var loadJob: Job? = null
    private var generation = 0

    init { load(initial = true) }

    fun refresh() = load(initial = state.value.list == null)

    fun focus(todoId: String?) {
        state.update { it.copy(focusId = todoId?.takeIf { id -> id.isNotBlank() }) }
        refresh()
    }

    fun startCreate() {
        if (state.value.draft?.saving == true) return
        state.update { it.copy(draft = TodoDraft(), message = null, actionError = null) }
    }

    fun startEdit(todo: PersonalTodo) {
        if (state.value.draft?.saving == true || todo.done) return
        state.update {
            it.copy(
                draft = TodoDraft(
                    editingId = todo.id,
                    title = todo.title,
                    note = todo.note,
                    dueAt = todo.dueAt,
                    remindAt = todo.remindAt,
                    previousRemindAt = todo.remindAt,
                ),
                message = null,
                actionError = null,
            )
        }
    }

    fun cancelDraft() {
        if (state.value.draft?.saving == true) return
        state.update { it.copy(draft = null) }
    }

    fun updateDraft(transform: (TodoDraft) -> TodoDraft) {
        state.update { current ->
            val draft = current.draft ?: return@update current
            if (draft.saving) return@update current
            current.copy(draft = transform(draft).copy(serverError = null))
        }
    }

    fun setTitle(value: String) = updateDraft { it.copy(title = value, errors = it.errors - "title") }
    fun setNote(value: String) = updateDraft { it.copy(note = value, errors = it.errors - "note") }
    fun setDueAt(value: Long?) = updateDraft { it.copy(dueAt = value, errors = it.errors - "due") }
    fun setRemindAt(value: Long?) = updateDraft { it.copy(remindAt = value, errors = it.errors - "remind") }

    fun saveDraft() {
        val draft = state.value.draft ?: return
        if (draft.saving) return
        val validation = PersonalTodoRules.validate(draft.title, draft.note, draft.dueAt, draft.remindAt, clock(), draft.previousRemindAt)
        val input = validation.input
        if (!validation.ok || input == null) {
            state.update { it.copy(draft = draft.copy(errors = validation.errors)) }
            return
        }
        state.update { it.copy(draft = draft.copy(errors = emptyMap(), saving = true, serverError = null)) }
        viewModelScope.launch {
            try {
                if (draft.editingId != null) repository.update(draft.editingId, input) else repository.create(input)
                state.update { it.copy(draft = null, message = if (draft.editingId != null) "Đã lưu việc." else "Đã thêm việc.") }
                load(initial = false)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                state.update { current -> current.copy(draft = current.draft?.copy(saving = false, serverError = todoErrorText(error))) }
            }
        }
    }

    fun setCompleted(todo: PersonalTodo, done: Boolean) {
        if (state.value.busyId != null || todo.done == done) return
        runAction(todo.id, success = null) { repository.setCompleted(todo.id, done) }
    }

    fun requestDelete(todo: PersonalTodo) {
        if (state.value.busyId != null) return
        state.update { it.copy(confirmDelete = todo) }
    }

    fun cancelDelete() {
        if (state.value.busyId != null) return
        state.update { it.copy(confirmDelete = null) }
    }

    fun confirmDelete() {
        val target = state.value.confirmDelete ?: return
        if (state.value.busyId != null) return
        runAction(target.id, success = "Đã xóa việc.") {
            repository.remove(target.id)
            state.update { current ->
                current.copy(
                    confirmDelete = null,
                    draft = current.draft?.takeIf { it.editingId != target.id },
                )
            }
        }
    }

    private fun runAction(id: String, success: String?, operation: suspend () -> Unit) {
        state.update { it.copy(busyId = id, message = null, actionError = null) }
        viewModelScope.launch {
            try {
                operation()
                state.update { it.copy(busyId = null, message = success) }
                load(initial = false)
            } catch (error: CancellationException) {
                state.update { it.copy(busyId = null) }
                throw error
            } catch (error: Exception) {
                state.update { it.copy(busyId = null, actionError = todoErrorText(error)) }
            }
        }
    }

    private fun load(initial: Boolean) {
        loadJob?.cancel()
        val version = ++generation
        state.update { it.copy(loading = initial, refreshing = !initial, error = null) }
        loadJob = viewModelScope.launch {
            try {
                val list = repository.listMine()
                if (version != generation) return@launch
                state.update { it.copy(loading = false, refreshing = false, list = list) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (version != generation) return@launch
                state.update { it.copy(loading = false, refreshing = false, error = todoErrorText(error)) }
            }
        }
    }

    companion object {
        fun factory(repository: PersonalTodoOperations): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T = PersonalTodosViewModel(repository) as T
            }
    }
}

internal fun todoErrorText(error: Throwable): String = when (error) {
    is IOException -> "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại."
    is JSONException -> "Phản hồi máy chủ không hợp lệ. Vui lòng thử lại."
    is ConvexException -> PersonalTodoRules.errorMessage("${error.code}\n${error.message}")
    else -> PersonalTodoRules.errorMessage(error.message)
}

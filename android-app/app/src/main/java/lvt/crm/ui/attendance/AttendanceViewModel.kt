package lvt.crm.ui.attendance

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
import lvt.crm.data.attendance.AttendanceClass
import lvt.crm.data.attendance.AttendanceOperations
import lvt.crm.data.attendance.AttendancePresentation
import lvt.crm.data.attendance.AttendanceRoster
import lvt.crm.data.attendance.AttendanceSaveResult
import lvt.crm.data.attendance.AttendanceSaved
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.homeroom.isVietnamDate
import org.json.JSONException

/** An action postponed until the user agrees to drop unsaved ticks of the open class. */
sealed interface AttendancePendingAction {
    data class SelectGrade(val grade: Int) : AttendancePendingAction
    data class SelectDate(val date: String) : AttendancePendingAction
    data class ToggleClass(val classId: String) : AttendancePendingAction
    data object Leave : AttendancePendingAction
}

data class AttendanceUiState(
    val loading: Boolean = true,
    val refreshing: Boolean = false,
    val error: String? = null,
    val roster: AttendanceRoster? = null,
    /** null = server default (today). Admin/mod may pick a past date. */
    val date: String? = null,
    val grade: Int = AttendancePresentation.gradeTabs.first(),
    val openClassId: String? = null,
    val draftAbsent: Set<String> = emptySet(),
    val saving: Boolean = false,
    val saveError: String? = null,
    val saveMessage: String? = null,
    val pendingAction: AttendancePendingAction? = null,
) {
    val openClass: AttendanceClass? get() = openClassId?.let { roster?.findClass(it) }

    /** True when the open class has ticks that differ from what the server last returned. */
    val dirty: Boolean get() = openClass?.let { it.absentIds != draftAbsent } ?: false
}

class AttendanceViewModel(private val repository: AttendanceOperations) : ViewModel() {
    private val state = MutableStateFlow(AttendanceUiState())
    val uiState: StateFlow<AttendanceUiState> = state.asStateFlow()
    private var loadJob: Job? = null
    private var generation = 0
    /** Set when the user agreed to leave; the screen consumes it and navigates away. */
    private val leave = MutableStateFlow(0)
    val leaveRequests: StateFlow<Int> = leave.asStateFlow()

    init { load(initial = true) }

    fun refresh() {
        if (state.value.saving) return
        load(initial = state.value.roster == null)
    }

    fun selectGrade(grade: Int) {
        if (grade == state.value.grade) return
        guard(AttendancePendingAction.SelectGrade(grade))
    }

    fun selectDate(date: String) {
        val current = state.value
        val roster = current.roster ?: return
        if (!roster.canChooseDate || !isVietnamDate(date) || date > roster.today || date == roster.date) return
        guard(AttendancePendingAction.SelectDate(date))
    }

    fun toggleClass(classId: String) {
        if (state.value.roster?.findClass(classId) == null) return
        guard(AttendancePendingAction.ToggleClass(classId))
    }

    /** System back / leaving the screen. Returns true when the caller may leave right away. */
    fun requestLeave(): Boolean {
        if (!state.value.dirty && !state.value.saving) return true
        if (state.value.saving) return false
        state.update { it.copy(pendingAction = AttendancePendingAction.Leave) }
        return false
    }

    fun confirmDiscard() {
        val action = state.value.pendingAction ?: return
        state.update { it.copy(pendingAction = null) }
        apply(action)
    }

    fun cancelDiscard() {
        state.update { it.copy(pendingAction = null) }
    }

    fun toggleAbsent(studentId: String) {
        val current = state.value
        val open = current.openClass ?: return
        if (current.saving || open.students.none { it.studentId == studentId }) return
        state.update { it.copy(draftAbsent = AttendancePresentation.toggle(it.draftAbsent, studentId), saveError = null, saveMessage = null) }
    }

    fun saveOpenClass() {
        val current = state.value
        val roster = current.roster ?: return
        val open = current.openClass ?: return
        if (current.saving || open.students.isEmpty()) return
        val absent = current.draftAbsent.filterTo(linkedSetOf()) { id -> open.students.any { it.studentId == id } }
        loadJob?.cancel()
        val version = ++generation
        state.update { it.copy(saving = true, refreshing = false, saveError = null, saveMessage = null) }
        loadJob = viewModelScope.launch {
            val result = try {
                repository.saveClass(roster.date, open.classId, absent)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                state.update { it.copy(saving = false, saveError = attendanceErrorText(error)) }
                return@launch
            }
            val message = AttendancePresentation.savedMessage(open.name, result)
            // The save is confirmed. Read the roster back; ticks stay locked until then.
            try {
                val fresh = repository.roster(roster.date)
                if (version != generation) return@launch
                val klass = fresh.findClass(open.classId)
                state.update {
                    it.copy(
                        saving = false,
                        roster = fresh,
                        openClassId = klass?.classId,
                        draftAbsent = klass?.absentIds ?: emptySet(),
                        saveMessage = message,
                    )
                }
            } catch (error: CancellationException) {
                state.update { it.copy(saving = false) }
                throw error
            } catch (error: Exception) {
                state.update {
                    it.copy(
                        saving = false,
                        roster = it.roster?.let { previous -> markSaved(previous, result, absent) },
                        draftAbsent = absent,
                        saveMessage = "$message Chưa tải lại được danh sách; kéo xuống để tải lại.",
                    )
                }
            }
        }
    }

    private fun guard(action: AttendancePendingAction) {
        if (state.value.saving) return
        if (state.value.dirty) {
            state.update { it.copy(pendingAction = action) }
            return
        }
        apply(action)
    }

    private fun apply(action: AttendancePendingAction) {
        when (action) {
            is AttendancePendingAction.SelectGrade -> state.update {
                it.copy(grade = action.grade, openClassId = null, draftAbsent = emptySet(), saveError = null, saveMessage = null)
            }
            is AttendancePendingAction.SelectDate -> {
                state.update { it.copy(date = action.date, openClassId = null, draftAbsent = emptySet(), saveError = null, saveMessage = null) }
                load(initial = true)
            }
            is AttendancePendingAction.ToggleClass -> state.update { current ->
                if (current.openClassId == action.classId) {
                    current.copy(openClassId = null, draftAbsent = emptySet(), saveError = null, saveMessage = null)
                } else {
                    val klass = current.roster?.findClass(action.classId)
                    current.copy(openClassId = action.classId, draftAbsent = klass?.absentIds ?: emptySet(), saveError = null, saveMessage = null)
                }
            }
            AttendancePendingAction.Leave -> {
                state.update { current -> current.copy(draftAbsent = current.openClass?.absentIds ?: emptySet()) }
                leave.update { it + 1 }
            }
        }
    }

    private fun load(initial: Boolean) {
        loadJob?.cancel()
        val version = ++generation
        val requestDate = state.value.date
        state.update { it.copy(loading = initial, refreshing = !initial, error = null) }
        loadJob = viewModelScope.launch {
            try {
                val roster = repository.roster(requestDate)
                if (version != generation) return@launch
                state.update { current ->
                    // Keep the open class and the user's ticks across a plain refresh.
                    val open = current.openClassId?.takeIf { roster.findClass(it) != null }
                    val draft = when {
                        open == null -> emptySet()
                        current.dirty -> current.draftAbsent.filterTo(linkedSetOf()) { id -> roster.findClass(open)!!.students.any { it.studentId == id } }
                        else -> roster.findClass(open)!!.absentIds
                    }
                    current.copy(loading = false, refreshing = false, roster = roster, date = roster.date, openClassId = open, draftAbsent = draft)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (version != generation) return@launch
                state.update { it.copy(loading = false, refreshing = false, error = attendanceErrorText(error)) }
            }
        }
    }

    /** Local copy of a confirmed save, used only when the read-back failed. */
    private fun markSaved(roster: AttendanceRoster, result: AttendanceSaveResult, absent: Set<String>): AttendanceRoster =
        roster.copy(
            grades = roster.grades.map { grade ->
                grade.copy(
                    classes = grade.classes.map { klass ->
                        if (klass.classId != result.classId) klass
                        else klass.copy(
                            saved = AttendanceSaved(result.savedAt, klass.saved?.savedByName.orEmpty(), "manual", result.presentCount, result.absentCount),
                            students = klass.students.map { it.copy(absent = it.studentId in absent) },
                        )
                    },
                )
            },
        )

    companion object {
        fun factory(repository: AttendanceOperations): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T = AttendanceViewModel(repository) as T
            }
    }
}

internal fun attendanceErrorText(error: Throwable): String = when (error) {
    is IOException -> "Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại."
    is JSONException -> AttendancePresentation.errorMessage("INVALID_RESPONSE")
    is ConvexException -> AttendancePresentation.errorMessage("${error.code}\n${error.message}")
    else -> AttendancePresentation.errorMessage(error.message)
}

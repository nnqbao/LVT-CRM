package lvt.crm.ui.homeroom

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import lvt.crm.data.homeroom.*

data class HomeroomDetailState(
    val context: DetailContext,
    val studentId: String? = null,
    val classData: ClassDetail? = null,
    val studentData: StudentDetail? = null,
    val loading: Boolean = false,
    /** Soft refresh after a confirmed write: the loaded class stays visible until fresh data arrives. */
    val refreshing: Boolean = false,
    val error: String? = null,
    /** Attendance day whose "Vắng không phép" toggle is being written. */
    val busyDayId: String? = null,
    val actionMessage: String? = null,
    val actionError: String? = null,
)

class HomeroomDetailViewModel(private val repository: HomeroomDetailOperations, context: DetailContext, val writeOperations: HomeroomWriteRepository? = null) : ViewModel() {
    private val state = MutableStateFlow(HomeroomDetailState(context))
    val uiState = state.asStateFlow()
    private var generation = 0
    private var job: Job? = null

    init { refresh() }

    fun refresh() = load(keepData = false)

    private fun load(keepData: Boolean) {
        job?.cancel()
        val version = ++generation
        if (keepData) {
            state.update { it.copy(error = null, refreshing = true) }
        } else {
            state.update { it.copy(classData = null, studentData = null, error = null, loading = true, refreshing = false, actionMessage = null, actionError = null) }
        }
        val request = state.value
        job = viewModelScope.launch {
            try {
                request.context.validate()
                val studentId = request.studentId
                val classData = if (studentId == null) repository.loadClass(request.context) else null
                val studentData = if (studentId != null) repository.loadStudent(request.context, studentId) else null
                if (version != generation) return@launch
                state.update { it.copy(classData = classData, studentData = studentData, loading = false, refreshing = false) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (version != generation) return@launch
                state.update { it.copy(classData = null, studentData = null, loading = false, refreshing = false, error = error.message ?: "Không tải được dữ liệu.") }
            }
        }
    }

    /**
     * GVCN / admin ticks "Vắng không phép" (unexcused) or unticks it (excused) for one absent day.
     * No reason is required; the existing reason/note are kept. The server re-checks scope.
     */
    fun setUnexcused(row: DailyRow, checked: Boolean) {
        val writes = writeOperations ?: return
        val current = state.value
        val data = current.classData ?: return
        val day = row.day ?: return
        if (current.busyDayId != null || current.studentId != null || current.loading) return
        if (!data.daily.canCorrect || data.daily.archived || day.rawObservation != "absent") return
        if (data.daily.rows.none { it.day?.id == day.id && it.student.id == row.student.id }) return
        val next = HomeroomPresentation.nextDispositionForToggle(checked)
        if (day.disposition == next) return
        val context = current.context
        val write = try {
            HomeroomWritePayload.disposition(AbsenceTarget(day.id, row.student.id, context, row.student.fullName), next, day.reasonCode.orEmpty(), day.note.orEmpty())
        } catch (error: Exception) {
            state.update { it.copy(actionError = error.message ?: "Không thể ghi thay đổi.") }
            return
        }
        state.update { it.copy(busyDayId = day.id, actionError = null, actionMessage = null) }
        viewModelScope.launch {
            try {
                writes.submit(write, { state.value.context == context && state.value.studentId == null })
                state.update { it.copy(busyDayId = null, actionMessage = "${row.student.fullName}: ${if (checked) "vắng không phép" else "vắng có phép"}.") }
                if (state.value.context == context && state.value.studentId == null) load(keepData = true)
            } catch (error: CancellationException) {
                state.update { it.copy(busyDayId = null) }
                throw error
            } catch (error: Exception) {
                val message = when {
                    error is WriteDenied || error is WriteUncertain -> error.message
                    error is lvt.crm.data.convex.ConvexException -> lvt.crm.data.convex.ConvexHttpClient.humanize(error.code)
                    else -> null
                } ?: "Không thể ghi thay đổi. Vui lòng thử lại."
                state.update { it.copy(busyDayId = null, actionError = message) }
                if (isHomeroomWriteDenied(error) || error is WriteUncertain) load(keepData = false).also { state.update { it.copy(actionError = message) } }
            }
        }
    }

    fun selectDate(date: String) {
        if (!isVietnamDate(date) || date == state.value.context.date) return
        state.update { it.copy(context = it.context.copy(date = date), studentId = null) }
        refresh()
    }

    fun openStudent(id: String) {
        val data = state.value.classData ?: return
        if (data.roster.rows.none { it.student.id == id } && data.daily.rows.none { it.student.id == id }) return
        state.update { it.copy(studentId = id) }
        refresh()
    }

    fun backToClass() {
        state.update { it.copy(studentId = null) }
        refresh()
    }

    fun selectHistoryRange(from: String, to: String) {
        if (!isVietnamDate(from) || !isVietnamDate(to) || from > to) return
        state.update { it.copy(context = it.context.copy(from = from, to = to)) }
        refresh()
    }

    fun close() {
        generation++
        job?.cancel()
        state.update { it.copy(classData = null, studentData = null, loading = false, refreshing = false, busyDayId = null, error = null) }
    }
    fun clearWriteData() { state.update { it.copy(classData = null, studentData = null) } }
}

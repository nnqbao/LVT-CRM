package lvt.crm.ui.boarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import lvt.crm.data.boarding.BoardingAdminData
import lvt.crm.data.boarding.BoardingAdminPeriod
import lvt.crm.data.boarding.BoardingErrorMessages
import lvt.crm.data.boarding.BoardingOperations
import lvt.crm.data.boarding.BoardingPeriodInput
import lvt.crm.data.boarding.BoardingReport
import lvt.crm.data.boarding.BoardingRules

enum class BoardingTab(val title: String) {
    Periods("Kỳ bán trú"),
    Participants("Danh sách tham gia"),
}

data class BoardingEditor(
    val editingId: String? = null,
    val semester: Int = 1,
    val schoolYear: String = BoardingRules.currentSchoolYear(),
    val participantUserIds: List<String> = emptyList(),
) {
    val input: BoardingPeriodInput get() = BoardingPeriodInput(semester, schoolYear, participantUserIds)
}

data class BoardingUiState(
    val canManage: Boolean = false,
    val tab: BoardingTab = BoardingTab.Participants,
    val reportLoading: Boolean = true,
    val reportError: String? = null,
    val report: BoardingReport? = null,
    val selectedPeriodId: String? = null,
    val adminLoading: Boolean = false,
    val adminError: String? = null,
    val admin: BoardingAdminData? = null,
    val editor: BoardingEditor? = null,
    val saving: Boolean = false,
    val pendingDelete: BoardingAdminPeriod? = null,
    val notice: String? = null,
    val actionError: String? = null,
    val currentSchoolYear: String = BoardingRules.currentSchoolYear(),
) {
    /** Admin/mod see both tabs; everyone else only the participant list (web BoardingPage). */
    val visibleTab: BoardingTab get() = if (canManage) tab else BoardingTab.Participants

    val refreshing: Boolean get() = (reportLoading && report != null) || (adminLoading && admin != null)
}

class BoardingViewModel(
    private val repository: BoardingOperations,
    canManage: Boolean,
) : ViewModel() {
    private val _uiState = MutableStateFlow(
        BoardingUiState(
            canManage = canManage,
            tab = if (canManage) BoardingTab.Periods else BoardingTab.Participants,
        ),
    )
    val uiState: StateFlow<BoardingUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        loadReport(_uiState.value.selectedPeriodId)
        if (_uiState.value.canManage) loadAdmin()
    }

    fun selectTab(tab: BoardingTab) {
        _uiState.update { it.copy(tab = tab, notice = null, actionError = null) }
    }

    fun selectPeriod(periodId: String) {
        _uiState.update { it.copy(selectedPeriodId = periodId) }
        loadReport(periodId)
    }

    private fun loadReport(periodId: String?) {
        _uiState.update { it.copy(reportLoading = true, reportError = null) }
        viewModelScope.launch {
            try {
                val report = try {
                    repository.report(periodId)
                } catch (error: Exception) {
                    // A period removed meanwhile (or now out of scope): fall back to the default one.
                    if (periodId != null && BoardingErrorMessages.hasCode(error, "BOARDING_PERIOD_FORBIDDEN")) {
                        repository.report(null)
                    } else {
                        throw error
                    }
                }
                _uiState.update {
                    it.copy(
                        reportLoading = false,
                        report = report,
                        selectedPeriodId = report.selectedPeriod?.id,
                    )
                }
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        reportLoading = false,
                        reportError = BoardingErrorMessages.messageFor(error, "Không tải được danh sách bán trú."),
                    )
                }
            }
        }
    }

    private fun loadAdmin() {
        _uiState.update { it.copy(adminLoading = true, adminError = null) }
        viewModelScope.launch {
            try {
                val admin = repository.listAdmin()
                _uiState.update { it.copy(adminLoading = false, admin = admin) }
            } catch (error: Exception) {
                _uiState.update {
                    it.copy(
                        adminLoading = false,
                        adminError = BoardingErrorMessages.messageFor(error, "Không tải được dữ liệu bán trú."),
                    )
                }
            }
        }
    }

    fun startCreate() {
        _uiState.update { it.copy(editor = BoardingEditor(), notice = null, actionError = null) }
    }

    fun startEdit(period: BoardingAdminPeriod) {
        _uiState.update {
            it.copy(
                editor = BoardingEditor(
                    editingId = period.period.id,
                    semester = period.period.semester,
                    schoolYear = period.period.schoolYear,
                    participantUserIds = period.participantUserIds,
                ),
                notice = null,
                actionError = null,
            )
        }
    }

    fun closeEditor() {
        _uiState.update { it.copy(editor = null, actionError = null) }
    }

    fun updateEditor(transform: (BoardingEditor) -> BoardingEditor) {
        _uiState.update { state -> state.copy(editor = state.editor?.let(transform)) }
    }

    fun save() {
        val state = _uiState.value
        val editor = state.editor ?: return
        if (state.saving) return
        BoardingRules.validate(editor.input)?.let { message ->
            _uiState.update { it.copy(actionError = message) }
            return
        }
        _uiState.update { it.copy(saving = true, actionError = null, notice = null) }
        viewModelScope.launch {
            try {
                if (editor.editingId != null) {
                    repository.update(editor.editingId, editor.input)
                } else {
                    repository.create(editor.input)
                }
                _uiState.update {
                    it.copy(
                        saving = false,
                        editor = null,
                        notice = if (editor.editingId != null) "Đã cập nhật kỳ bán trú." else "Đã thêm kỳ bán trú.",
                    )
                }
                refresh()
            } catch (error: Exception) {
                _uiState.update { it.copy(saving = false, actionError = BoardingErrorMessages.messageFor(error)) }
            }
        }
    }

    fun requestDelete(period: BoardingAdminPeriod) {
        _uiState.update { it.copy(pendingDelete = period, notice = null, actionError = null) }
    }

    fun dismissDelete() {
        _uiState.update { it.copy(pendingDelete = null) }
    }

    fun confirmDelete() {
        val target = _uiState.value.pendingDelete ?: return
        if (_uiState.value.saving) return
        _uiState.update { it.copy(saving = true, pendingDelete = null, actionError = null, notice = null) }
        viewModelScope.launch {
            try {
                repository.remove(target.period.id)
                _uiState.update {
                    it.copy(
                        saving = false,
                        notice = "Đã xóa kỳ bán trú.",
                        editor = it.editor?.takeUnless { editor -> editor.editingId == target.period.id },
                        selectedPeriodId = it.selectedPeriodId?.takeUnless { id -> id == target.period.id },
                    )
                }
                refresh()
            } catch (error: Exception) {
                _uiState.update { it.copy(saving = false, actionError = BoardingErrorMessages.messageFor(error)) }
            }
        }
    }

    companion object {
        fun factory(repository: BoardingOperations, canManage: Boolean): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    BoardingViewModel(repository, canManage) as T
            }
    }
}

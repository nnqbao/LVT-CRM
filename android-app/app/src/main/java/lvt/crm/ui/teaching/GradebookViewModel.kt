package lvt.crm.ui.teaching

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.teaching.ClassStudents
import lvt.crm.data.teaching.GradeEntry
import lvt.crm.data.teaching.GradeMath
import lvt.crm.data.teaching.GradebookClasses
import lvt.crm.data.teaching.StudentRecord
import lvt.crm.data.teaching.TeachingCatalog
import lvt.crm.data.teaching.TeachingOperations
import lvt.crm.data.teaching.TeachingSchedule

/** Thêm điểm / Sửa điểm dialog. [entry] is null when adding. */
data class ScoreEditor(
    val entry: GradeEntry?,
    val subjectId: String,
    val semester: Int,
    /** Empty while editing an entry whose Loại kiểm tra was removed: the server keeps the old one. */
    val testTypeId: String,
    val scoreText: String,
    val confirmDelete: Boolean = false,
    val saving: Boolean = false,
    val error: String? = null,
) {
    val score: Double? get() = GradeMath.parseScore(scoreText)
    val scoreInvalid: Boolean get() = scoreText.isNotBlank() && score == null
    val keepsRemovedType: Boolean get() = entry != null && testTypeId.isBlank()
    val valid: Boolean get() = score != null && subjectId.isNotBlank() && (testTypeId.isNotBlank() || keepsRemovedType)
}

data class GradebookUiState(
    val yearId: String? = null,
    val classesLoading: Boolean = false,
    val classes: GradebookClasses? = null,
    val classesError: String? = null,
    val catalog: TeachingCatalog? = null,
    val openClassId: String? = null,
    val studentsLoading: Boolean = false,
    val students: ClassStudents? = null,
    val studentsError: String? = null,
    val openStudentId: String? = null,
    /** School year chip chosen on the student record; null = the server default. */
    val recordYearId: String? = null,
    val recordLoading: Boolean = false,
    val record: StudentRecord? = null,
    val recordError: String? = null,
    val editor: ScoreEditor? = null,
    val message: String? = null,
)

/** Lớp học › Học bạ: lớp → học sinh → học bạ, with Thêm / Sửa / Xóa điểm. Server re-checks every call. */
class GradebookViewModel(
    private val repository: TeachingOperations,
    private val today: () -> String = { TeachingSchedule.vietnamNow().date },
) : ViewModel() {
    private val _uiState = MutableStateFlow(GradebookUiState())
    val uiState: StateFlow<GradebookUiState> = _uiState.asStateFlow()
    private var classesJob: Job? = null
    private var studentsJob: Job? = null
    private var recordJob: Job? = null

    fun setYear(yearId: String?) {
        if (yearId == null || _uiState.value.yearId == yearId && (_uiState.value.classes != null || _uiState.value.classesLoading)) return
        _uiState.update { GradebookUiState(yearId = yearId, catalog = it.catalog) }
        loadClasses()
    }

    fun refresh() {
        val state = _uiState.value
        when {
            state.openStudentId != null -> loadRecord()
            state.openClassId != null -> loadStudents()
            else -> loadClasses()
        }
    }

    private fun loadClasses() {
        val yearId = _uiState.value.yearId ?: return
        classesJob?.cancel()
        _uiState.update { it.copy(classesLoading = true, classesError = null) }
        classesJob = viewModelScope.launch {
            try {
                val classes = repository.gradebookClasses(yearId)
                val catalog = _uiState.value.catalog ?: runCatching { repository.catalog() }.getOrNull()
                if (_uiState.value.yearId != yearId) return@launch
                _uiState.update { it.copy(classesLoading = false, classes = classes, catalog = catalog) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(classesLoading = false, classesError = message(e)) }
            }
        }
    }

    fun openClass(classId: String) {
        _uiState.update { it.copy(openClassId = classId, students = null, openStudentId = null, record = null, message = null) }
        loadStudents()
    }

    fun closeClass() {
        studentsJob?.cancel()
        _uiState.update { it.copy(openClassId = null, students = null, studentsError = null, studentsLoading = false) }
    }

    private fun loadStudents() {
        val classId = _uiState.value.openClassId ?: return
        studentsJob?.cancel()
        _uiState.update { it.copy(studentsLoading = true, studentsError = null) }
        studentsJob = viewModelScope.launch {
            try {
                val students = repository.classStudents(classId)
                if (_uiState.value.openClassId != classId) return@launch
                _uiState.update { it.copy(studentsLoading = false, students = students) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(studentsLoading = false, studentsError = message(e)) }
            }
        }
    }

    fun openStudent(studentId: String) {
        _uiState.update { it.copy(openStudentId = studentId, recordYearId = null, record = null, editor = null, message = null) }
        loadRecord()
    }

    fun closeStudent() {
        recordJob?.cancel()
        _uiState.update { it.copy(openStudentId = null, record = null, recordError = null, recordLoading = false, editor = null) }
    }

    fun selectRecordYear(yearId: String) {
        val state = _uiState.value
        if (state.record?.selectedYearId == yearId || state.record?.years?.none { it.id == yearId } == true) return
        _uiState.update { it.copy(recordYearId = yearId, editor = null) }
        loadRecord()
    }

    private fun loadRecord(keep: Boolean = false) {
        val studentId = _uiState.value.openStudentId ?: return
        val yearId = _uiState.value.recordYearId
        recordJob?.cancel()
        _uiState.update { it.copy(recordLoading = true, recordError = null, record = if (keep) it.record else null) }
        recordJob = viewModelScope.launch {
            try {
                val record = repository.studentRecord(studentId, yearId)
                if (_uiState.value.openStudentId != studentId || _uiState.value.recordYearId != yearId) return@launch
                _uiState.update { it.copy(recordLoading = false, record = record) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(recordLoading = false, recordError = message(e)) }
            }
        }
    }

    // ------------------------------------------------------------ score editor

    fun startAdd() {
        val record = _uiState.value.record ?: return
        if (!record.canAdd) return
        val year = record.selectedYear
        _uiState.update {
            it.copy(
                message = null,
                editor = ScoreEditor(
                    entry = null,
                    subjectId = record.writableSubjectIds.first(),
                    semester = TeachingSchedule.semesterForDate(today(), year?.semester2StartDate),
                    testTypeId = record.testTypes.first().id,
                    scoreText = "",
                ),
            )
        }
    }

    fun startEdit(entry: GradeEntry) {
        val record = _uiState.value.record ?: return
        if (!entry.canEdit || record.selectedYear?.locked == true) return
        _uiState.update {
            it.copy(
                message = null,
                editor = ScoreEditor(
                    entry = entry,
                    subjectId = entry.subjectId,
                    semester = entry.semester,
                    testTypeId = entry.testTypeId.takeIf { id -> record.testTypes.any { type -> type.id == id } }.orEmpty(),
                    scoreText = GradeMath.editableScore(entry.score),
                ),
            )
        }
    }

    fun updateEditor(transform: (ScoreEditor) -> ScoreEditor) {
        _uiState.update { state ->
            val editor = state.editor ?: return@update state
            if (editor.saving) return@update state
            state.copy(editor = transform(editor).copy(error = null))
        }
    }

    fun closeEditor() = _uiState.update { state -> if (state.editor?.saving == true) state else state.copy(editor = null) }

    fun saveEditor() {
        val state = _uiState.value
        val record = state.record ?: return
        val editor = state.editor ?: return
        val score = editor.score ?: return
        if (editor.saving || !editor.valid) return
        _uiState.update { it.copy(editor = editor.copy(saving = true, error = null)) }
        viewModelScope.launch {
            try {
                val entry = editor.entry
                if (entry == null) {
                    repository.addGrade(record.student.id, record.selectedClassId, editor.subjectId, editor.semester, editor.testTypeId, score)
                } else {
                    repository.updateGrade(entry.id, editor.semester, editor.testTypeId.ifBlank { entry.testTypeId }, score)
                }
                _uiState.update { it.copy(editor = null, message = if (entry == null) "Đã thêm điểm." else "Đã lưu điểm.") }
                loadRecord(keep = true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(editor = it.editor?.copy(saving = false, error = message(e))) }
            }
        }
    }

    fun deleteEditorEntry() {
        val editor = _uiState.value.editor ?: return
        val entry = editor.entry ?: return
        if (editor.saving) return
        _uiState.update { it.copy(editor = editor.copy(saving = true, error = null)) }
        viewModelScope.launch {
            try {
                repository.removeGrade(entry.id)
                _uiState.update { it.copy(editor = null, message = "Đã xóa điểm.") }
                loadRecord(keep = true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(editor = it.editor?.copy(saving = false, error = message(e))) }
            }
        }
    }

    private fun message(error: Throwable): String =
        (error as? ConvexException)?.message ?: ConvexHttpClient.humanize(error.message ?: "LOAD_FAILED")

    companion object {
        fun factory(repository: TeachingOperations): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T = GradebookViewModel(repository) as T
            }
    }
}

package lvt.crm.ui.teaching

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.homeroom.HomeroomOverview
import lvt.crm.data.homeroom.SchoolYear
import lvt.crm.data.teaching.Lesson
import lvt.crm.data.teaching.MyLessonLog
import lvt.crm.data.teaching.MyTeaching
import lvt.crm.data.teaching.TeacherSchedule
import lvt.crm.data.teaching.TeachingCatalog
import lvt.crm.data.teaching.TeachingOperations
import lvt.crm.data.teaching.TeachingSchedule
import lvt.crm.data.teaching.VietnamNow

/** Sổ đầu bài form for one class (Lớp giảng dạy). */
data class LessonLogForm(
    val classId: String,
    val className: String,
    val date: String,
    val lessons: List<Lesson>,
    /** `session-period` of the chosen lesson. */
    val cell: String?,
    /** Own logs of that class on [date]; null while loading. */
    val existing: List<MyLessonLog>? = null,
    val rating: Int = 0,
    val comment: String = "",
    val saving: Boolean = false,
    val error: String? = null,
) {
    val current: Lesson? get() = lessons.firstOrNull { it.cellKey == cell }
    val saved: MyLessonLog? get() = existing?.firstOrNull { "${it.session}-${it.period}" == cell }
}

data class TeachingUiState(
    val now: VietnamNow = TeachingSchedule.vietnamNow(),
    val years: List<SchoolYear> = emptyList(),
    val selectedYearId: String? = null,
    val loading: Boolean = true,
    val refreshing: Boolean = false,
    val error: String? = null,
    val teaching: MyTeaching? = null,
    val catalog: TeachingCatalog? = null,
    /** `homeroomReports:overview` of today for "Học sinh vắng hôm nay". */
    val homeroomOverview: HomeroomOverview? = null,
    val homeroomError: String? = null,
    val schedule: TeacherSchedule? = null,
    val scheduleLoading: Boolean = false,
    val scheduleError: String? = null,
    val form: LessonLogForm? = null,
    val message: String? = null,
)

/** Lớp học › Tổng quan, Lớp giảng dạy (+ Sổ đầu bài), Lịch dạy. Server re-checks every call. */
class TeachingViewModel(
    private val repository: TeachingOperations,
    private val clock: () -> VietnamNow = { TeachingSchedule.vietnamNow() },
) : ViewModel() {
    private val _uiState = MutableStateFlow(TeachingUiState(now = clock()))
    val uiState: StateFlow<TeachingUiState> = _uiState.asStateFlow()
    private var loadJob: Job? = null
    private var scheduleJob: Job? = null
    private var formJob: Job? = null
    private var generation = 0
    private var formGeneration = 0

    init { load(initial = true) }

    fun refresh() = load(initial = false)

    fun selectYear(id: String) {
        val current = _uiState.value
        if (current.selectedYearId == id || current.years.none { it.id == id }) return
        _uiState.update { it.copy(selectedYearId = id, teaching = null, schedule = null, homeroomOverview = null, form = null) }
        load(initial = true)
    }

    private fun load(initial: Boolean) {
        loadJob?.cancel()
        val version = ++generation
        val now = clock()
        val requested = _uiState.value.selectedYearId
        val reloadSchedule = _uiState.value.schedule != null || _uiState.value.scheduleError != null
        _uiState.update { it.copy(now = now, loading = initial, refreshing = !initial, error = null) }
        loadJob = viewModelScope.launch {
            try {
                val years = repository.schoolYears().sortedBy { it.startDate }
                val yearId = requested?.takeIf { id -> years.any { it.id == id } }
                    ?: years.firstOrNull { it.active }?.id
                    ?: years.lastOrNull()?.id
                if (version != generation) return@launch
                if (yearId == null) {
                    _uiState.update { it.copy(loading = false, refreshing = false, years = years, selectedYearId = null) }
                    return@launch
                }
                coroutineScope {
                    val teaching = async { repository.myTeaching(yearId) }
                    val catalog = async { repository.catalog() }
                    val overview = async { runCatching { repository.homeroomOverview(yearId, now.date) } }
                    val teachingValue = teaching.await()
                    val catalogValue = catalog.await()
                    val overviewValue = overview.await()
                    if (version != generation) return@coroutineScope
                    _uiState.update {
                        it.copy(
                            loading = false,
                            refreshing = false,
                            years = years,
                            selectedYearId = yearId,
                            teaching = teachingValue,
                            catalog = catalogValue,
                            homeroomOverview = overviewValue.getOrNull(),
                            homeroomError = overviewValue.exceptionOrNull()?.let(::message),
                        )
                    }
                }
                if (reloadSchedule && version == generation) loadSchedule(force = true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (version != generation) return@launch
                _uiState.update { it.copy(loading = false, refreshing = false, error = message(e)) }
            }
        }
    }

    /** Lịch dạy is loaded when its section opens. */
    fun ensureSchedule() {
        val state = _uiState.value
        if (state.schedule != null || state.scheduleLoading || state.selectedYearId == null) return
        loadSchedule(force = false)
    }

    private fun loadSchedule(force: Boolean) {
        val yearId = _uiState.value.selectedYearId ?: return
        if (!force && _uiState.value.scheduleLoading) return
        scheduleJob?.cancel()
        _uiState.update { it.copy(scheduleLoading = true, scheduleError = null) }
        scheduleJob = viewModelScope.launch {
            try {
                val schedule = repository.schedule(yearId)
                if (_uiState.value.selectedYearId != yearId) return@launch
                _uiState.update { it.copy(schedule = schedule, scheduleLoading = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { it.copy(scheduleLoading = false, scheduleError = message(e)) }
            }
        }
    }

    fun retrySchedule() = loadSchedule(force = true)

    // ------------------------------------------------------------ Sổ đầu bài form

    fun openLessonLog(classId: String) {
        val data = _uiState.value.teaching ?: return
        val klass = data.classes.firstOrNull { it.id == classId } ?: return
        val now = clock()
        val date = TeachingPresentation.lessonLogMaxDate(data, now)
        _uiState.update { it.copy(now = now, message = null) }
        showDate(LessonLogForm(classId, klass.name, date, emptyList(), null), date)
    }

    fun closeLessonLog() {
        formJob?.cancel()
        formGeneration++
        _uiState.update { it.copy(form = null) }
    }

    fun selectLogDate(date: String) {
        val form = _uiState.value.form ?: return
        val data = _uiState.value.teaching ?: return
        val max = TeachingPresentation.lessonLogMaxDate(data, clock())
        if (date < data.year.startDate || date > max || date == form.date || form.saving) return
        showDate(form, date)
    }

    private fun showDate(base: LessonLogForm, date: String) {
        val data = _uiState.value.teaching ?: return
        val lessons = TeachingPresentation.lessonsOfClass(data, base.classId, date)
        val cell = TeachingSchedule.defaultLesson(lessons, date, clock())?.cellKey
        formJob?.cancel()
        val version = ++formGeneration
        _uiState.update {
            it.copy(form = base.copy(date = date, lessons = lessons, cell = cell, existing = null, rating = 0, comment = "", error = null))
        }
        formJob = viewModelScope.launch {
            try {
                val existing = repository.myLogsFor(base.classId, date)
                if (version != formGeneration) return@launch
                _uiState.update { state ->
                    val form = state.form ?: return@update state
                    state.copy(form = form.copy(existing = existing).prefilled())
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (version != formGeneration) return@launch
                _uiState.update { state ->
                    state.copy(form = state.form?.copy(existing = emptyList(), error = message(e)))
                }
            }
        }
    }

    fun selectLogCell(cell: String) {
        _uiState.update { state ->
            val form = state.form ?: return@update state
            if (form.saving || form.lessons.none { it.cellKey == cell }) return@update state
            state.copy(form = form.copy(cell = cell, error = null).prefilled())
        }
    }

    fun setRating(rating: Int) {
        if (rating !in 1..5) return
        _uiState.update { state -> state.copy(form = state.form?.copy(rating = rating, error = null)) }
    }

    fun setComment(comment: String) {
        _uiState.update { state -> state.copy(form = state.form?.copy(comment = comment.take(LESSON_COMMENT_MAX), error = null)) }
    }

    fun saveLessonLog() {
        val state = _uiState.value
        val form = state.form ?: return
        val lesson = form.current ?: return
        if (form.saving || form.existing == null || form.rating !in 1..5 || state.teaching?.year?.locked == true) return
        _uiState.update { it.copy(form = form.copy(saving = true, error = null)) }
        viewModelScope.launch {
            try {
                repository.saveLessonLog(form.classId, form.date, lesson.session, lesson.period, form.rating, form.comment.trim())
                formGeneration++
                _uiState.update { it.copy(form = null, message = "Đã lưu Sổ đầu bài.") }
                refreshTeachingQuietly()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _uiState.update { current ->
                    current.copy(form = current.form?.copy(saving = false, error = message(e)))
                }
            }
        }
    }

    fun clearMessage() = _uiState.update { it.copy(message = null) }

    private fun refreshTeachingQuietly() {
        val yearId = _uiState.value.selectedYearId ?: return
        viewModelScope.launch {
            runCatching { repository.myTeaching(yearId) }.onSuccess { teaching ->
                if (_uiState.value.selectedYearId == yearId) _uiState.update { it.copy(teaching = teaching, now = clock()) }
            }
        }
    }

    private fun LessonLogForm.prefilled(): LessonLogForm {
        val saved = saved
        return copy(rating = saved?.rating ?: 0, comment = saved?.comment ?: "")
    }

    private fun message(error: Throwable): String =
        (error as? ConvexException)?.message ?: ConvexHttpClient.humanize(error.message ?: "LOAD_FAILED")

    companion object {
        const val LESSON_COMMENT_MAX = 1000

        fun factory(repository: TeachingOperations): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T = TeachingViewModel(repository) as T
            }
    }
}

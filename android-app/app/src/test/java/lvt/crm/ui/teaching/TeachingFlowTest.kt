package lvt.crm.ui.teaching

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.teaching.ClassLessonLog
import lvt.crm.data.teaching.MyLessonLog
import lvt.crm.data.teaching.TodayLessonLog
import lvt.crm.data.teaching.VietnamNow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TeachingFlowTest {
    private val dispatcher = StandardTestDispatcher()
    // Thứ 4 21/10/2026, 08:00: tiết 1 sáng của 6A1 vừa dạy, tiết 4 chưa tới.
    private val now = VietnamNow("2026-10-21", "08:00")

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test
    fun teachingRowsPutTheNearestNextLessonFirst() {
        val rows = TeachingPresentation.teachingRows(testTeaching(), testCatalog, now)
        assertEquals(listOf("6A1", "8A3", "7A2", "9A1"), rows.map { it.klass.name })
        assertTrue(rows[0].isToday)
        assertEquals("Hôm nay · Tiết 4 sáng · 09:40", rows[0].nextLabel)
        assertEquals("Thứ 6, 23/10/2026 · Tiết 2 sáng · 07:50", rows[2].nextLabel)
        assertEquals("Ngữ văn", rows[2].subjects)
        assertEquals("Không còn tiết nào trong 5 tuần tới", rows[3].nextLabel)
    }

    @Test
    fun todayLessonsShowLoggedState() {
        val data = testTeaching(todayLogs = listOf(TodayLessonLog("l1", "c1", "2026-10-21", "morning", 1, 5, "")))
        val rows = TeachingPresentation.todayLessons(data, testCatalog, now)
        assertEquals(listOf("07:00", "09:40", "13:30"), rows.map { it.time })
        assertEquals("6A1 · Toán", rows[0].title)
        assertEquals(listOf(true, false, false), rows.map { it.logged })
    }

    @Test
    fun weeklyAverageUsesVietnameseDecimal() {
        fun log(rating: Int) = ClassLessonLog("$rating", "2026-10-21", "morning", 1, "Cô A", "Toán", rating, "", 0.0, 0.0)
        assertEquals("4,3", TeachingPresentation.weeklyAverage(listOf(log(5), log(4), log(4))))
        assertEquals("", TeachingPresentation.weeklyAverage(emptyList()))
    }

    @Test
    fun lessonLogFormDefaultsPrefillsAndSaves() = runTest(dispatcher) {
        val repository = FakeTeachingOperations()
        repository.myLogs["c1" to "2026-10-21"] = listOf(MyLessonLog("x", "morning", 1, 4, "Lớp trật tự", 1.0))
        val viewModel = TeachingViewModel(repository) { now }
        advanceUntilIdle()
        assertEquals("y1", viewModel.uiState.value.selectedYearId)
        assertEquals(1, viewModel.uiState.value.homeroomOverview?.classes?.size)

        viewModel.openLessonLog("c1")
        advanceUntilIdle()
        var form = viewModel.uiState.value.form!!
        assertEquals("2026-10-21", form.date)
        assertEquals("morning-1", form.cell)
        assertEquals(4, form.rating)
        assertEquals("Lớp trật tự", form.comment)

        viewModel.selectLogCell("morning-4")
        form = viewModel.uiState.value.form!!
        assertEquals(0, form.rating)
        viewModel.saveLessonLog()
        advanceUntilIdle()
        assertTrue("no rating → nothing saved", repository.saved.isEmpty())

        viewModel.setRating(5)
        viewModel.setComment("  Tốt  ")
        viewModel.saveLessonLog()
        advanceUntilIdle()
        assertEquals(listOf(listOf("c1", "2026-10-21", "morning", 4, 5, "Tốt")), repository.saved)
        assertNull(viewModel.uiState.value.form)
        assertEquals("Đã lưu Sổ đầu bài.", viewModel.uiState.value.message)
    }

    @Test
    fun lessonLogRejectsFutureDatesAndShowsServerErrors() = runTest(dispatcher) {
        val repository = FakeTeachingOperations()
        repository.saveError = ConvexException("LESSON_NOT_SCHEDULED", ConvexHttpClient.humanize("Uncaught Error: LESSON_NOT_SCHEDULED"))
        val viewModel = TeachingViewModel(repository) { now }
        advanceUntilIdle()
        viewModel.openLessonLog("c1")
        advanceUntilIdle()
        viewModel.selectLogDate("2026-10-22")
        assertEquals("2026-10-21", viewModel.uiState.value.form?.date)
        viewModel.selectLogDate("2026-10-20") // Thứ 3: 6A1 has no lesson
        advanceUntilIdle()
        assertTrue(viewModel.uiState.value.form!!.lessons.isEmpty())
        viewModel.selectLogDate("2026-10-14")
        advanceUntilIdle()
        viewModel.setRating(3)
        viewModel.saveLessonLog()
        advanceUntilIdle()
        val form = viewModel.uiState.value.form!!
        assertFalse(form.saving)
        assertEquals("Bạn không có tiết này ở lớp vào ngày đã chọn.", form.error)
    }

    @Test
    fun gradebookEditorAddsAndEditsScores() = runTest(dispatcher) {
        val repository = FakeTeachingOperations()
        val viewModel = GradebookViewModel(repository) { "2027-02-01" }
        viewModel.setYear("y1")
        viewModel.openClass("c1")
        viewModel.openStudent("st1")
        advanceUntilIdle()
        val record = viewModel.uiState.value.record!!
        assertTrue(record.canAdd)

        viewModel.startAdd()
        var editor = viewModel.uiState.value.editor!!
        assertEquals("semester from semester2StartDate", 2, editor.semester)
        assertEquals("toan", editor.subjectId)
        assertEquals("m", editor.testTypeId)
        viewModel.updateEditor { it.copy(scoreText = "10,5") }
        assertTrue(viewModel.uiState.value.editor!!.scoreInvalid)
        viewModel.saveEditor()
        advanceUntilIdle()
        assertTrue(repository.added.isEmpty())
        viewModel.updateEditor { it.copy(scoreText = "8,75") }
        viewModel.saveEditor()
        advanceUntilIdle()
        assertEquals(listOf(listOf("st1", "c1", "toan", 2, "m", 8.75)), repository.added)
        assertEquals("Đã thêm điểm.", viewModel.uiState.value.message)

        // Own score whose Loại kiểm tra was removed: keep the old type on save.
        val own = viewModel.uiState.value.record!!.entries.first { it.id == "g1" }
        viewModel.startEdit(own)
        editor = viewModel.uiState.value.editor!!
        assertEquals("7,5", editor.scoreText)
        assertTrue(editor.keepsRemovedType)
        viewModel.saveEditor()
        advanceUntilIdle()
        assertEquals(listOf(listOf("g1", 1, "removed", 7.5)), repository.updated)

        // Someone else's score is read-only.
        viewModel.startEdit(viewModel.uiState.value.record!!.entries.first { it.id == "g2" })
        assertNull(viewModel.uiState.value.editor)

        viewModel.startEdit(own)
        viewModel.updateEditor { it.copy(confirmDelete = true) }
        viewModel.deleteEditorEntry()
        advanceUntilIdle()
        assertEquals(listOf("g1"), repository.removed)
        assertEquals("Đã xóa điểm.", viewModel.uiState.value.message)
    }
}

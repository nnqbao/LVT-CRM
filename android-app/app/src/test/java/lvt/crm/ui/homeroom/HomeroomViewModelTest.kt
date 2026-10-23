package lvt.crm.ui.homeroom

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import lvt.crm.data.homeroom.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HomeroomViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    @Before fun setup() { Dispatchers.setMain(dispatcher) }
    @After fun teardown() { Dispatchers.resetMain() }

    @Test fun `overview loads for the selected year and date without the pending inbox`() = runTest(dispatcher) {
        val repository = RecordingHomeroomOperations()
        val viewModel = HomeroomViewModel(repository)
        advanceUntilIdle()
        assertEquals(1, repository.overviewCalls)
        assertEquals("test-year", viewModel.uiState.value.overview?.schoolYear?.id)
        viewModel.selectDate("2026-02-30")
        viewModel.selectYear("not-returned-by-server")
        advanceUntilIdle()
        assertEquals(1, repository.overviewCalls)
        assertNull(viewModel.uiState.value.error)
    }

    @Test fun `empty years do not request attendance and errors remain errors`() = runTest(dispatcher) {
        val empty = RecordingHomeroomOperations(emptyYears = true)
        val emptyModel = HomeroomViewModel(empty)
        advanceUntilIdle()
        assertFalse(emptyModel.uiState.value.loading)
        assertTrue(emptyModel.uiState.value.years.isEmpty())
        assertEquals(0, empty.overviewCalls)
        val forbidden = RecordingHomeroomOperations(deny = true)
        val forbiddenModel = HomeroomViewModel(forbidden)
        advanceUntilIdle()
        assertNotNull(forbiddenModel.uiState.value.error)
        assertNull(forbiddenModel.uiState.value.overview)
    }

    @Test fun `focusing a class from Lớp học overview switches to that day`() = runTest(dispatcher) {
        val repository = RecordingHomeroomOperations()
        val viewModel = HomeroomViewModel(repository)
        advanceUntilIdle()
        viewModel.focusClass("test-year", "2026-10-07", "class-not-in-scope")
        advanceUntilIdle()
        assertEquals("2026-10-07", viewModel.uiState.value.date)
        assertEquals("2026-10-07", viewModel.uiState.value.overview?.date)
        assertNull("out-of-scope class does not open", viewModel.detailState.value)
    }

    @Test fun `cancelled older request cannot overwrite newer date`() = runTest(dispatcher) {
        val repository = RecordingHomeroomOperations(blockFirst = true)
        val viewModel = HomeroomViewModel(repository)
        runCurrent()
        viewModel.selectDate("2026-10-06")
        runCurrent()
        assertEquals("2026-10-06", viewModel.uiState.value.date)
        assertEquals("2026-10-06", viewModel.uiState.value.overview?.date)
        repository.release.complete(Unit)
        advanceUntilIdle()
        assertEquals("2026-10-06", viewModel.uiState.value.overview?.date)
        assertNull(viewModel.uiState.value.error)
    }
}

private class RecordingHomeroomOperations(
    private val emptyYears: Boolean = false,
    private val deny: Boolean = false,
    private val blockFirst: Boolean = false,
) : HomeroomOperations {
    var overviewCalls = 0
    val release = CompletableDeferred<Unit>()
    override suspend fun listSchoolYears(): List<SchoolYear> = if (emptyYears) emptyList() else
        listOf(SchoolYear("test-year", "Test year", "2026-08-01", "2027-06-01", true))
    override suspend fun overview(schoolYearId: String, date: String): HomeroomOverview {
        val call = ++overviewCalls
        if (deny) error("HOMEROOM_SCOPE_FORBIDDEN")
        if (blockFirst && call == 1) withContext(NonCancellable) { release.await() }
        return decodeOverview(org.json.JSONObject("""{"date":"$date","today":"$date","mode":"teacher",
            "schoolYear":{"_id":"$schoolYearId","name":"Test year"},"classes":[],"schoolDay":{},"missingUpload":{},
            "summary":{"counts":{"present":0,"late":0,"absent_excused":0,"absent_unexcused":0,"no_data":0,"absent_pending":0,"exempt":0}}}"""))
    }
}

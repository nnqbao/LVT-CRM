package lvt.crm.ui.boarding

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.boarding.BoardingAdminData
import lvt.crm.data.boarding.BoardingAdminPeriod
import lvt.crm.data.boarding.BoardingOperations
import lvt.crm.data.boarding.BoardingPeriod
import lvt.crm.data.boarding.BoardingPeriodInput
import lvt.crm.data.boarding.BoardingReport
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BoardingViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun nonManagersOnlyGetTheListAndNeverCallAdmin() = runTest(dispatcher) {
        val repo = FakeBoarding()
        val vm = BoardingViewModel(repo, canManage = false)
        advanceUntilIdle()
        assertEquals(BoardingTab.Participants, vm.uiState.value.visibleTab)
        vm.selectTab(BoardingTab.Periods)
        assertEquals(BoardingTab.Participants, vm.uiState.value.visibleTab)
        assertEquals(0, repo.adminCalls)
        assertEquals("p1", vm.uiState.value.selectedPeriodId)
    }

    @Test
    fun managersValidateBeforeSavingAndDeleteAfterConfirm() = runTest(dispatcher) {
        val repo = FakeBoarding()
        val vm = BoardingViewModel(repo, canManage = true)
        advanceUntilIdle()
        assertEquals(BoardingTab.Periods, vm.uiState.value.visibleTab)
        vm.startCreate()
        vm.save()
        assertEquals("Vui lòng chọn ít nhất một giáo viên.", vm.uiState.value.actionError)
        assertEquals(0, repo.created.size)
        vm.updateEditor { it.copy(semester = 2, schoolYear = "2026-2027", participantUserIds = listOf("u1")) }
        vm.save()
        advanceUntilIdle()
        assertEquals(BoardingPeriodInput(2, "2026-2027", listOf("u1")), repo.created.single())
        assertNull(vm.uiState.value.editor)
        assertEquals("Đã thêm kỳ bán trú.", vm.uiState.value.notice)

        val period = repo.adminData.periods.single()
        vm.requestDelete(period)
        assertEquals(period, vm.uiState.value.pendingDelete)
        vm.confirmDelete()
        advanceUntilIdle()
        assertEquals(listOf("p1"), repo.removed)
        assertEquals("Đã xóa kỳ bán trú.", vm.uiState.value.notice)
    }

    private class FakeBoarding : BoardingOperations {
        var adminCalls = 0
        val created = mutableListOf<BoardingPeriodInput>()
        val removed = mutableListOf<String>()
        private val period = BoardingPeriod("p1", 1, "2026-2027", 1)
        val adminData = BoardingAdminData(
            users = emptyList(),
            periods = listOf(BoardingAdminPeriod(period, listOf("u1"), emptyList())),
        )

        override suspend fun report(periodId: String?) = BoardingReport(
            visibilityScope = "all",
            periods = listOf(period),
            selectedPeriod = period,
            groups = emptyList(),
            totalParticipants = 0,
        )

        override suspend fun listAdmin(): BoardingAdminData {
            adminCalls++
            return adminData
        }

        override suspend fun create(input: BoardingPeriodInput): String {
            created += input
            return "p-new"
        }

        override suspend fun update(id: String, input: BoardingPeriodInput) = Unit

        override suspend fun remove(id: String) {
            removed += id
        }
    }
}

package lvt.crm.ui.home

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.duties.DutiesOperations
import lvt.crm.data.duties.DutiesSnapshot
import lvt.crm.data.duties.DutyItem
import lvt.crm.data.work.WorkApprovalItem
import lvt.crm.data.work.WorkCompletionReviewItem
import lvt.crm.data.work.WorkOperations
import lvt.crm.data.work.WorkSnapshot
import lvt.crm.data.work.WorkTaskItem
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DashboardViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun countsMatchIosDashboardRules() = runTest(dispatcher) {
        val viewModel = DashboardViewModel(
            dutiesRepository = object : DutiesOperations {
                override suspend fun listMine() = DutiesSnapshot(
                    attendanceConfirmationEnabled = true,
                    duties = listOf(
                        duty(upcoming = true),
                        duty(ongoing = true),
                        duty(ongoing = true),
                    ),
                )

                override suspend fun setAttendance(dutyId: String, status: String) = Unit
            },
            workRepository = object : WorkOperations {
                override suspend fun listMine() = WorkSnapshot(
                    assignerMode = "",
                    isAdmin = false,
                    accessLevel = 4,
                    tasks = listOf(
                        task(status = "pending_task"),
                        task(status = "completed"),
                    ),
                    approvals = listOf(
                        approval(decision = ""),
                        approval(decision = "approved"),
                    ),
                    completionReviews = listOf(
                        WorkCompletionReviewItem("w1", "u1", "A", "c", "2026-08-12", "PB"),
                    ),
                )

                override suspend fun complete(
                    item: WorkTaskItem,
                    qualityPercent: Int?,
                    evidence: lvt.crm.data.work.WorkUploadedEvidence?,
                    note: String?,
                    documentTypeId: String?,
                ) = Unit
                override suspend fun decideApproval(documentId: String, approve: Boolean, reason: String?) = Unit
                override suspend fun reviewCompletion(
                    review: WorkCompletionReviewItem,
                    approve: Boolean,
                    qualityPercent: Int?,
                    rejectionReason: String?,
                ) = Unit
            },
        )
        advanceUntilIdle()
        val state = viewModel.uiState.value
        assertEquals(1, state.upcomingDuties)
        assertEquals(2, state.ongoingDuties)
        assertEquals(1, state.pendingApproval)
        assertEquals(1, state.pendingExecution)
    }

    private fun duty(upcoming: Boolean = false, ongoing: Boolean = false) = DutyItem(
        id = java.util.UUID.randomUUID().toString(),
        content = "Họp",
        startDate = "2026-08-12",
        endDate = "2026-08-12",
        startTime = "08:00",
        endTime = "09:00",
        allDay = false,
        locationNames = emptyList(),
        departmentNames = emptyList(),
        departmentParticipants = emptyList(),
        participantNames = emptyList(),
        myStatus = "pending",
        isMine = true,
        isOngoing = ongoing,
        isOverdue = false,
        isUpcoming = upcoming,
        canMarkAttendance = true,
    )

    private fun task(status: String) = WorkTaskItem(
        id = java.util.UUID.randomUUID().toString(),
        kind = WorkTaskItem.Kind.WorkItem,
        title = "Task",
        deadline = "2026-08-12",
        status = status,
        documentContent = "",
        departmentName = "",
        qualityPercent = null,
        rejectionReason = "",
        isAdmin = false,
    )

    private fun approval(decision: String) = WorkApprovalItem(
        id = java.util.UUID.randomUUID().toString(),
        fileName = "cv.pdf",
        content = "",
        deadline = "2026-08-12",
        status = "pending",
        approvalCount = 0,
        approvalTotal = 1,
        myDecision = decision,
    )
}

package lvt.crm.ui.work

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import lvt.crm.data.work.WorkApprovalItem
import lvt.crm.data.work.WorkApprovalPolicy
import lvt.crm.data.work.WorkCompletionReviewItem
import lvt.crm.data.work.WorkCreateAssignment
import lvt.crm.data.work.WorkDocumentAssignment
import lvt.crm.data.work.WorkFormOptions
import lvt.crm.data.work.WorkOperations
import lvt.crm.data.work.WorkSnapshot
import lvt.crm.data.work.WorkTaskItem
import lvt.crm.data.work.WorkUploadedEvidence
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class WorkApprovalFlowTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun returnWithoutReasonIsBlockedLocally() = runTest(dispatcher) {
        val repo = FakeOperations()
        val vm = WorkViewModel(repo)
        advanceUntilIdle()
        val doc = queued("doc-1")
        assertFalse(vm.decideApproval(doc, approve = false, reason = "  "))
        advanceUntilIdle()
        assertEquals(0, repo.decisions.size)
        assertEquals(WorkApprovalPolicy.RETURN_REASON_REQUIRED_MESSAGE, vm.uiState.value.actionError)

        assertTrue(vm.decideApproval(doc, approve = false, reason = " Thiếu số liệu "))
        advanceUntilIdle()
        assertEquals(Triple("doc-1", false, "Thiếu số liệu"), repo.decisions.single())
        assertEquals("Đã trả lại công việc cho người tạo.", vm.uiState.value.notice)
    }

    @Test
    fun approveSendsNoReasonAndQueueSplitsAwaitingFromHistory() = runTest(dispatcher) {
        val repo = FakeOperations()
        val vm = WorkViewModel(repo)
        advanceUntilIdle()
        assertEquals(listOf("doc-1"), vm.uiState.value.awaitingApprovals.map { it.id })
        assertEquals(listOf("doc-old"), vm.uiState.value.decidedApprovals.map { it.id })
        assertEquals("me", vm.uiState.value.currentUserId)
        vm.decideApproval(queued("doc-1"), approve = true)
        advanceUntilIdle()
        assertEquals(Triple("doc-1", true, null), repo.decisions.single())
    }

    @Test
    fun opsCreateRequiresApproverUnlessOnlyAssigningThemselves() = runTest(dispatcher) {
        val repo = FakeOperations()
        val vm = WorkViewModel(repo)
        advanceUntilIdle()
        vm.loadFormOptions()
        advanceUntilIdle()
        val forOthers = listOf(WorkCreateAssignment("individual", userIds = listOf("t1"), content = "Báo cáo", deadline = "2026-11-01"))
        vm.createDocument("Kế hoạch", forOthers, onSuccess = {})
        advanceUntilIdle()
        assertEquals(WorkApprovalPolicy.APPROVER_REQUIRED_MESSAGE, vm.uiState.value.actionError)
        assertEquals(0, repo.created.size)

        vm.createDocument("Kế hoạch", forOthers, approverIds = listOf("bgh-1"), onSuccess = {})
        advanceUntilIdle()
        assertEquals(listOf("bgh-1"), repo.created.single())
        assertEquals(
            "Đã gửi công việc cho Ban giám hiệu duyệt. Người nhận sẽ thấy sau khi được duyệt.",
            vm.uiState.value.notice,
        )

        val self = listOf(WorkCreateAssignment("individual", userIds = listOf("me"), content = "Lưu", deadline = "2026-11-01"))
        vm.createDocument("Tự làm", self, onSuccess = {})
        advanceUntilIdle()
        assertNull(repo.created.last())
        assertEquals("Đã tạo công việc.", vm.uiState.value.notice)
    }

    @Test
    fun awaitingApprovalDocumentsSitInTheWaitingTab() {
        val doc = queued("doc-9").copy(
            workStatus = "awaiting_approval",
            assignments = listOf(
                WorkDocumentAssignment("i1", "Tổ Toán", "x", "2099-01-01", "unassigned", emptyList()),
            ),
        )
        assertEquals(WorkListTab.PendingReview, tabForDocument(doc, today = "2026-10-22"))
        val returned = doc.copy(status = "rejected", workStatus = "approval_returned")
        assertEquals(WorkListTab.Todo, tabForDocument(returned, today = "2026-10-22"))
        assertEquals("Chờ duyệt" to lvt.crm.ui.components.StatusTone.Primary, documentStatusChip(doc))
        assertEquals("Bị trả lại", documentStatusChip(returned).first)
        val released = doc.copy(status = "approved", workStatus = "in_progress")
        assertEquals("Đang thực hiện", documentStatusChip(released).first)
    }

    private fun queued(id: String) = WorkApprovalItem(
        id = id,
        fileName = "",
        content = "",
        deadline = "2026-11-01",
        status = "pending",
        approvalCount = 0,
        approvalTotal = 1,
        myDecision = "",
        requiresApproval = true,
        awaitingMyDecision = true,
        canReject = true,
    )

    private inner class FakeOperations : WorkOperations {
        val decisions = mutableListOf<Triple<String, Boolean, String?>>()
        val created = mutableListOf<List<String>?>()

        override suspend fun listMine() = WorkSnapshot(
            assignerMode = "admin_mod",
            isAdmin = true,
            accessLevel = 5,
            tasks = emptyList(),
            approvals = emptyList(),
            canCreate = true,
            isOps = true,
            approvalQueue = listOf(
                queued("doc-old").copy(awaitingMyDecision = false, status = "approved", submittedAt = 5),
                queued("doc-1").copy(submittedAt = 1),
            ),
            currentUserId = "me",
        )

        override suspend fun formOptions() = WorkFormOptions(
            canCreate = true,
            isOps = true,
            departments = emptyList(),
            users = emptyList(),
            requiresApproval = true,
            canAssignDepartments = true,
        )

        override suspend fun createDocument(
            title: String,
            assignments: List<WorkCreateAssignment>,
            evidence: WorkUploadedEvidence?,
            documentTypeId: String?,
            approverUserIds: List<String>?,
        ): String {
            created += approverUserIds
            return "new-doc"
        }

        override suspend fun complete(
            item: WorkTaskItem,
            qualityPercent: Int?,
            evidence: WorkUploadedEvidence?,
            note: String?,
            documentTypeId: String?,
        ) = Unit

        override suspend fun decideApproval(documentId: String, approve: Boolean, reason: String?) {
            decisions += Triple(documentId, approve, reason)
        }

        override suspend fun reviewCompletion(
            review: WorkCompletionReviewItem,
            approve: Boolean,
            qualityPercent: Int?,
            rejectionReason: String?,
        ) = Unit
    }
}

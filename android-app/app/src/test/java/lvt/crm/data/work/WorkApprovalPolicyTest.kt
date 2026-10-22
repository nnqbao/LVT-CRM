package lvt.crm.data.work

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkApprovalPolicyTest {
    private val others = listOf(
        WorkCreateAssignment(type = "individual", userIds = listOf("teacher-1"), content = "Báo cáo", deadline = "2026-11-01"),
    )
    private val selfOnly = listOf(
        WorkCreateAssignment(type = "individual", userIds = listOf("me"), content = "Lưu trữ", deadline = "2026-11-01"),
    )

    @Test
    fun opsCreatedWorkForOthersNeedsAnApprover() {
        assertTrue(WorkApprovalPolicy.approverRequired(requiresApproval = true, others, "me"))
        assertEquals(
            WorkApprovalPolicy.APPROVER_REQUIRED_MESSAGE,
            WorkApprovalPolicy.validateApprovers(true, others, "me", emptyList()),
        )
        assertNull(WorkApprovalPolicy.validateApprovers(true, others, "me", listOf("bgh-1")))
        // Non-ops creators (tổ trưởng, Ban giám hiệu) release immediately.
        assertNull(WorkApprovalPolicy.validateApprovers(false, others, "me", emptyList()))
    }

    @Test
    fun selfOnlyAssignmentLeavesTheDecisionToTheServer() {
        assertTrue(WorkApprovalPolicy.isSelfOnlyAssignment(selfOnly, "me"))
        assertFalse(WorkApprovalPolicy.approverRequired(true, selfOnly, "me"))
        assertNull(WorkApprovalPolicy.validateApprovers(true, selfOnly, "me", emptyList()))
        // A department row or another person is never "self only".
        val mixed = selfOnly + WorkCreateAssignment(type = "department", departmentId = "d1", content = "x", deadline = "2026-11-01")
        assertFalse(WorkApprovalPolicy.isSelfOnlyAssignment(mixed, "me"))
        assertFalse(WorkApprovalPolicy.isSelfOnlyAssignment(selfOnly, ""))
        assertFalse(WorkApprovalPolicy.isSelfOnlyAssignment(emptyList(), "me"))
    }

    @Test
    fun submitLabelsMatchTheWeb() {
        assertEquals("Gửi duyệt", WorkApprovalPolicy.submitLabel(editing = false, needsApproval = true))
        assertEquals("Lưu và gửi duyệt lại", WorkApprovalPolicy.submitLabel(editing = true, needsApproval = true))
        assertEquals("Lưu thay đổi", WorkApprovalPolicy.submitLabel(editing = true, needsApproval = false))
        assertEquals("Tạo công việc", WorkApprovalPolicy.submitLabel(editing = false, needsApproval = false))
    }

    @Test
    fun statusProgressAndReturnReason() {
        val returned = document(status = "rejected").copy(
            approvalTotal = 2,
            returnReason = "Thiếu số liệu",
            approvers = listOf(
                WorkApproverView("bgh-1", "Hiệu trưởng", rejected = true, decidedAt = 1_793_000_000_000L, reason = "Thiếu số liệu"),
                WorkApproverView("bgh-2", "Hiệu phó"),
            ),
        )
        assertEquals("Bị trả lại", WorkApprovalPolicy.approvalStatusLabel(returned.status))
        assertEquals("Chờ duyệt", WorkApprovalPolicy.approvalStatusLabel("pending"))
        assertEquals("Đã duyệt", WorkApprovalPolicy.approvalStatusLabel("approved"))
        assertEquals("Ban giám hiệu duyệt 0/2", WorkApprovalPolicy.progressLabel(returned))
        assertEquals("Thiếu số liệu", WorkApprovalPolicy.returnReason(returned))
        assertNull(WorkApprovalPolicy.returnReason(returned.copy(status = "pending")))
        assertTrue(WorkApprovalPolicy.approverDecisionLabel(returned.approvers[0]).startsWith("Trả lại "))
        assertEquals("Chờ duyệt", WorkApprovalPolicy.approverDecisionLabel(returned.approvers[1]))
        assertTrue(WorkApprovalPolicy.isUnreleased(returned))
        assertFalse(WorkApprovalPolicy.isUnreleased(returned.copy(status = "approved")))
        assertFalse(WorkApprovalPolicy.isUnreleased(document(status = "approved").copy(requiresApproval = false)))
    }

    @Test
    fun vietnamDateTimeAndCreatorLabel() {
        // 2026-10-22 07:05 UTC = 14:05 in Vietnam.
        assertEquals("22/10/2026 14:05", WorkApprovalPolicy.formatDateTime(1_792_652_700_000L))
        assertEquals("", WorkApprovalPolicy.formatDateTime(null))
        assertEquals(
            "Người tạo: Lan (Văn thư)",
            WorkApprovalPolicy.creatorLabel(document("pending").copy(creatorName = "Lan", creatorRole = "moderator")),
        )
        assertEquals(
            "Người tạo: Minh",
            WorkApprovalPolicy.creatorLabel(document("approved").copy(creatorName = "Minh", creatorRole = "user")),
        )
    }

    @Test
    fun returnReasonIsRequiredAndBounded() {
        assertEquals(WorkApprovalPolicy.RETURN_REASON_REQUIRED_MESSAGE, WorkApprovalPolicy.validateReturnReason("   "))
        assertNull(WorkApprovalPolicy.validateReturnReason("Sửa hạn chót"))
        assertTrue(WorkApprovalPolicy.validateReturnReason("x".repeat(501)) != null)
    }

    @Test
    fun queueOrdersAwaitingFirstThenNewestSubmission() {
        val decidedNew = document("approved").copy(id = "decided", submittedAt = 300)
        val awaitingOld = document("pending").copy(id = "old", awaitingMyDecision = true, submittedAt = 100)
        val awaitingNew = document("pending").copy(id = "new", awaitingMyDecision = true, submittedAt = 200)
        assertEquals(
            listOf("new", "old", "decided"),
            WorkApprovalPolicy.orderedQueue(listOf(decidedNew, awaitingOld, awaitingNew)).map { it.id },
        )
    }

    @Test
    fun editKeepsOnlyApproversStillOffered() {
        val doc = document("rejected").copy(
            approvers = listOf(WorkApproverView("bgh-1", "A"), WorkApproverView("gone", "B")),
        )
        assertEquals(
            listOf("bgh-1"),
            WorkApprovalPolicy.editApproverIds(doc, listOf(WorkFormUser("bgh-1", "A", "", 5))),
        )
    }

    @Test
    fun decodesManagedDocumentWithApprovalFields() {
        val json = JSONObject(
            """
            {"_id":"doc-1","title":"Kế hoạch","fileName":"","content":"Nội dung","deadline":"2026-11-01",
             "status":"rejected","workStatus":"approval_returned","requiresApproval":true,"approvalLocked":false,
             "approvalCount":0,"approvalTotal":2,"submittedAt":1793084700000,"decidedAt":1793090000000,
             "returnReason":"Thiếu số liệu","creatorName":"Lan","creatorRole":"moderator",
             "canEdit":true,"canDelete":true,
             "approvers":[{"_id":"bgh-1","name":"Hiệu trưởng","level":5,"approved":false,"rejected":true,
                           "decidedAt":1793090000000,"reason":"Thiếu số liệu"},
                          {"_id":"bgh-2","name":"Hiệu phó","level":4,"approved":false,"rejected":false,"decidedAt":null,"reason":""}],
             "assignments":[{"_id":"item-1","type":"individual","departmentName":"Cá nhân","content":"Làm",
                             "deadline":"2026-11-01","status":"in_progress","taskCount":1,
                             "members":[{"_id":"u1","name":"An","status":"pending_task"}]}]}
            """.trimIndent(),
        )
        val doc = parseApproval(json, "")
        assertEquals("approval_returned", doc.workStatus)
        assertTrue(doc.requiresApproval)
        assertFalse(doc.approvalLocked)
        assertEquals(1_793_084_700_000L, doc.submittedAt)
        assertEquals(1_793_090_000_000L, doc.decidedAt)
        assertEquals("Thiếu số liệu", doc.returnReason)
        assertEquals("moderator", doc.creatorRole)
        assertEquals(2, doc.approvers.size)
        assertTrue(doc.approvers[0].rejected)
        assertNull(doc.approvers[1].decidedAt)
        assertEquals(1, doc.assignments.single().taskCount)
        assertFalse(doc.awaitingMyDecision)
    }

    @Test
    fun decodesApprovalQueueWithMyDecision() {
        val queue = JSONArray(
            """
            [{"_id":"doc-2","title":"Chờ duyệt","status":"pending","approvalCount":1,"approvalTotal":2,
              "awaitingMyDecision":false,"canReject":false,"submittedAt":10,
              "approvers":[{"_id":"me","name":"Tôi","approved":true,"rejected":false},
                           {"_id":"bgh-2","name":"Khác","approved":false,"rejected":false}],
              "assignments":[{"_id":"i1","type":"department","departmentName":"Tổ Toán","content":"x",
                              "deadline":"2026-11-02","status":"unassigned","taskCount":4}]},
             {"_id":"doc-3","title":"Mới","status":"pending","approvalCount":0,"approvalTotal":1,
              "awaitingMyDecision":true,"canReject":true,"submittedAt":20,
              "approvers":[{"_id":"me","name":"Tôi","approved":false,"rejected":false}],"assignments":[]}]
            """.trimIndent(),
        )
        val parsed = parseApprovalQueue(queue, "me")
        assertEquals("approved", parsed[0].myDecision)
        assertFalse(parsed[0].awaitingMyDecision)
        assertEquals(4, parsed[0].assignments.single().taskCount)
        assertTrue(parsed[0].assignments.single().members.isEmpty())
        assertEquals("", parsed[1].myDecision)
        assertTrue(parsed[1].awaitingMyDecision)
        assertTrue(parsed[1].canReject)
        assertTrue(parseApprovalQueue(null, "me").isEmpty())
    }

    @Test
    fun decodesFormOptionsFlagsAndApprovers() {
        val ops = parseWorkFormOptions(
            JSONObject(
                """
                {"canCreate":true,"isOps":true,"requiresApproval":true,"canAssignDepartments":true,
                 "departments":[{"_id":"d1","name":"Tổ Toán"}],
                 "users":[{"_id":"u1","name":"An","departmentName":"Tổ Toán","level":1,"positionName":"Giáo viên"}],
                 "approvers":[{"_id":"bgh-1","name":"Hiệu trưởng","level":5,"positionName":"Hiệu trưởng"}]}
                """.trimIndent(),
            ),
            emptyList(),
        )
        assertTrue(ops.requiresApproval)
        assertTrue(ops.canAssignDepartments)
        assertEquals("Hiệu trưởng", ops.approvers.single().positionName)
        assertEquals(5, ops.approvers.single().level)

        val bgh = parseWorkFormOptions(
            JSONObject("""{"canCreate":true,"isOps":false,"requiresApproval":false,"canAssignDepartments":true,"departments":[],"users":[],"approvers":[]}"""),
            emptyList(),
        )
        assertFalse(bgh.requiresApproval)
        assertTrue(bgh.canAssignDepartments)
        assertTrue(bgh.approvers.isEmpty())

        // Older server without the flag: only admin/mod assign whole departments.
        val legacyLead = parseWorkFormOptions(JSONObject("""{"canCreate":true,"isOps":false}"""), emptyList())
        assertFalse(legacyLead.canAssignDepartments)
        assertFalse(legacyLead.requiresApproval)
    }

    private fun document(status: String) = WorkApprovalItem(
        id = "doc",
        fileName = "",
        content = "",
        deadline = "2026-11-01",
        status = status,
        approvalCount = 0,
        approvalTotal = 1,
        myDecision = "",
        requiresApproval = true,
    )
}

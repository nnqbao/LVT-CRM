package lvt.crm.data.work

import java.util.Calendar
import java.util.TimeZone

/**
 * Ban giám hiệu approval presentation rules, mirroring the web (`src/work/workDisplay.js`,
 * `WorkApprovalParts.jsx`). The server stays the source of truth: these helpers only
 * decide labels and which controls to show from the flags it returns.
 */
object WorkApprovalPolicy {
    const val APPROVAL_NOTE = "Công việc do Văn thư/Quản trị tạo cần Ban giám hiệu duyệt trước khi giao."
    const val APPROVER_REQUIRED_MESSAGE = "Vui lòng chọn người duyệt thuộc Ban giám hiệu."
    const val RETURN_REASON_REQUIRED_MESSAGE = "Vui lòng nhập lý do trả lại."
    const val RETURN_REASON_MAX_LENGTH = 500
    const val UNRELEASED_LABEL = "Chờ duyệt (chưa giao)"
    const val REAPPROVAL_WARNING =
        "Công việc đã được duyệt. Sau khi lưu, công việc sẽ phải gửi Ban giám hiệu duyệt lại và tạm ẩn với người được giao."

    /**
     * Approval-required and not approved yet: nothing has been handed to the assignees, so
     * assignments read "Chờ duyệt (chưa giao)" instead of task progress.
     */
    fun isUnreleased(document: WorkApprovalItem): Boolean =
        document.requiresApproval && document.status != "approved"

    /** Whether the document follows the approval flow (now or in its history). */
    fun followsApproval(document: WorkApprovalItem): Boolean =
        document.requiresApproval || document.approvalTotal > 0 || document.approvers.isNotEmpty()

    /**
     * The only assignee is the creator (individual rows that all point at [currentUserId]).
     * The server may release such work without Ban giám hiệu approval, so the form does not
     * insist on approvers; it still sends any it collected and lets the server decide.
     */
    fun isSelfOnlyAssignment(assignments: List<WorkCreateAssignment>, currentUserId: String): Boolean {
        if (currentUserId.isBlank() || assignments.isEmpty()) return false
        return assignments.all { row ->
            val ids = row.userIds.filter { it.isNotBlank() }
            row.isIndividual && ids.isNotEmpty() && ids.all { it == currentUserId }
        }
    }

    /** Client-side approver requirement (UX only; the server re-checks with WORK_APPROVER_REQUIRED). */
    fun approverRequired(
        requiresApproval: Boolean,
        assignments: List<WorkCreateAssignment>,
        currentUserId: String,
    ): Boolean = requiresApproval && !isSelfOnlyAssignment(assignments, currentUserId)

    fun validateApprovers(
        requiresApproval: Boolean,
        assignments: List<WorkCreateAssignment>,
        currentUserId: String,
        approverIds: List<String>,
    ): String? = if (
        approverRequired(requiresApproval, assignments, currentUserId) &&
        approverIds.none { it.isNotBlank() }
    ) {
        APPROVER_REQUIRED_MESSAGE
    } else {
        null
    }

    fun submitLabel(editing: Boolean, needsApproval: Boolean): String = when {
        editing && needsApproval -> "Lưu và gửi duyệt lại"
        editing -> "Lưu thay đổi"
        needsApproval -> "Gửi duyệt"
        else -> "Tạo công việc"
    }

    fun savedNotice(editing: Boolean, needsApproval: Boolean): String = when {
        editing && needsApproval -> "Đã lưu và gửi Ban giám hiệu duyệt lại."
        needsApproval -> "Đã gửi công việc cho Ban giám hiệu duyệt. Người nhận sẽ thấy sau khi được duyệt."
        editing -> "Đã cập nhật công việc."
        else -> "Đã tạo công việc."
    }

    /** Keep only approvers still offered by the server (active Ban giám hiệu); the server re-validates. */
    fun editApproverIds(document: WorkApprovalItem, options: List<WorkFormUser>): List<String> {
        val eligible = options.mapTo(mutableSetOf()) { it.id }
        return document.approvers.map { it.id }.filter { it in eligible }
    }

    /** Document status chip for approval-flow documents: Chờ duyệt / Đã duyệt / Bị trả lại. */
    fun approvalStatusLabel(status: String): String = when (status) {
        "approved" -> "Đã duyệt"
        "rejected" -> "Bị trả lại"
        else -> "Chờ duyệt"
    }

    fun progressLabel(document: WorkApprovalItem): String {
        val total = document.approvalTotal.takeIf { it > 0 } ?: document.approvers.size
        return "Ban giám hiệu duyệt ${document.approvalCount}/$total"
    }

    /** Approver chip: "Đã duyệt 22/10/2026 14:05", "Trả lại …" or "Chờ duyệt". */
    fun approverDecisionLabel(approver: WorkApproverView): String {
        val time = formatDateTime(approver.decidedAt)
        return when {
            approver.approved -> if (time.isNotEmpty()) "Đã duyệt $time" else "Đã duyệt"
            approver.rejected -> if (time.isNotEmpty()) "Trả lại $time" else "Trả lại"
            else -> "Chờ duyệt"
        }
    }

    fun creatorRoleLabel(role: String): String = when (role) {
        "admin" -> "Quản trị viên"
        "moderator" -> "Văn thư"
        else -> ""
    }

    fun creatorLabel(document: WorkApprovalItem): String {
        val name = document.creatorName.ifBlank { "—" }
        val role = creatorRoleLabel(document.creatorRole)
        return "Người tạo: $name${if (role.isNotEmpty()) " ($role)" else ""}"
    }

    fun returnReason(document: WorkApprovalItem): String? =
        document.returnReason.trim().takeIf { document.status == "rejected" && it.isNotEmpty() }

    /** "Chờ tôi duyệt" first (newest submission first), then decided documents (30-day history). */
    fun orderedQueue(queue: List<WorkApprovalItem>): List<WorkApprovalItem> = queue.sortedWith(
        compareByDescending<WorkApprovalItem> { it.awaitingMyDecision }.thenByDescending { it.submittedAt },
    )

    fun validateReturnReason(reason: String): String? {
        val trimmed = reason.trim()
        return when {
            trimmed.isEmpty() -> RETURN_REASON_REQUIRED_MESSAGE
            trimmed.length > RETURN_REASON_MAX_LENGTH -> "Lý do trả lại tối đa $RETURN_REASON_MAX_LENGTH ký tự."
            else -> null
        }
    }

    /**
     * Whether saving this form must go through Ban giám hiệu: an admin re-editing an approved
     * document always does; otherwise approval-required work for someone other than the creator.
     */
    fun needsApproval(
        requiresApproval: Boolean,
        reapproval: Boolean,
        assignments: List<WorkCreateAssignment>,
        currentUserId: String,
    ): Boolean = reapproval || approverRequired(requiresApproval, assignments, currentUserId)

    /** HH:mm dd/MM/yyyy in Vietnam time; empty when unknown. */
    fun formatTimeDate(millis: Long?): String {
        val value = formatDateTime(millis)
        if (value.isEmpty()) return ""
        val (date, time) = value.split(' ')
        return "$time $date"
    }

    /** dd/MM/yyyy HH:mm in Vietnam time; empty when unknown. */
    fun formatDateTime(millis: Long?): String {
        if (millis == null || millis <= 0L) return ""
        val calendar = Calendar.getInstance(TimeZone.getTimeZone("GMT+07:00"))
        calendar.timeInMillis = millis
        return "%02d/%02d/%04d %02d:%02d".format(
            calendar.get(Calendar.DAY_OF_MONTH),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.HOUR_OF_DAY),
            calendar.get(Calendar.MINUTE),
        )
    }
}

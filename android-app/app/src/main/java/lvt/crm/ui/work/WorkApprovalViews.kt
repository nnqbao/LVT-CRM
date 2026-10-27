package lvt.crm.ui.work

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import lvt.crm.data.work.WorkApprovalItem
import lvt.crm.data.work.WorkApprovalPolicy
import lvt.crm.data.work.WorkDocumentActions
import lvt.crm.ui.components.StatusPill
import lvt.crm.ui.components.StatusTone

/** Pending approval decision chosen from a card or the detail screen. */
data class WorkDecisionRequest(
    val document: WorkApprovalItem,
    val approve: Boolean,
)

internal fun approvalStatusTone(status: String): StatusTone = when (status) {
    "approved" -> StatusTone.Positive
    "rejected" -> StatusTone.Warning
    else -> StatusTone.Primary
}

/** Status chip of a managed document: approval state while unreleased, otherwise progress. */
@Composable
internal fun WorkDocumentStatusPill(document: WorkApprovalItem) {
    val (label, tone) = documentStatusChip(document)
    StatusPill(label = label, tone = tone)
}

/** Unreleased approval documents show Chờ duyệt / Bị trả lại; released ones show their progress. */
internal fun documentStatusChip(document: WorkApprovalItem): Pair<String, StatusTone> = when {
    WorkApprovalPolicy.followsApproval(document) && document.status != "approved" ->
        WorkApprovalPolicy.approvalStatusLabel(document.status) to approvalStatusTone(document.status)
    document.workStatus.isNotBlank() ->
        workStatusLabel(document.workStatus) to workStatusTone(document.workStatus)
    else -> "Đã duyệt" to StatusTone.Positive
}

/** "Ban giám hiệu duyệt x/y", per-approver chips and the return reason. */
@Composable
internal fun WorkApprovalProgressBlock(document: WorkApprovalItem, modifier: Modifier = Modifier) {
    if (!WorkApprovalPolicy.followsApproval(document)) return
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            WorkApprovalPolicy.progressLabel(document),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        if (document.approvers.isNotEmpty()) {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                document.approvers.forEach { approver ->
                    StatusPill(
                        label = "${approver.name} · ${WorkApprovalPolicy.approverDecisionLabel(approver)}",
                        tone = when {
                            approver.approved -> StatusTone.Positive
                            approver.rejected -> StatusTone.Warning
                            else -> StatusTone.Neutral
                        },
                    )
                }
            }
        }
        WorkApprovalPolicy.returnReason(document)?.let { reason ->
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    "Lý do trả lại: $reason",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(12.dp),
                )
            }
        }
    }
}

/** Approve / Trả lại buttons (Trả lại only while nobody has approved). */
@Composable
internal fun WorkDecisionButtons(
    document: WorkApprovalItem,
    busy: Boolean,
    onDecide: (WorkDecisionRequest) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (!document.awaitingMyDecision) return
    Row(modifier = modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (document.canReject) {
            OutlinedButton(
                onClick = { onDecide(WorkDecisionRequest(document, approve = false)) },
                enabled = !busy,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text("Trả lại") }
        }
        Button(
            onClick = { onDecide(WorkDecisionRequest(document, approve = true)) },
            enabled = !busy,
            modifier = Modifier.weight(1f),
        ) { Text("Duyệt") }
    }
}

/** One document in "Chờ tôi duyệt" (or its 30-day history). */
@Composable
internal fun WorkApprovalQueueCard(
    document: WorkApprovalItem,
    focused: Boolean,
    busy: Boolean,
    onOpen: () -> Unit,
    onOpenFile: () -> Unit,
    onDecide: (WorkDecisionRequest) -> Unit,
) {
    Card(
        onClick = onOpen,
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(
            if (focused) 2.dp else 1.dp,
            if (focused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
        ),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    buildString {
                        append(WorkApprovalPolicy.creatorLabel(document))
                        WorkApprovalPolicy.formatDateTime(document.submittedAt).takeIf { it.isNotEmpty() }
                            ?.let { append(" · gửi $it") }
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                StatusPill(
                    label = WorkApprovalPolicy.approvalStatusLabel(document.status),
                    tone = approvalStatusTone(document.status),
                )
            }
            Text(workListTitle(document), style = MaterialTheme.typography.titleMedium)
            if (document.privateFile && document.fileName.isNotBlank()) {
                TextButton(onClick = onOpenFile, enabled = !busy) { Text(document.fileName) }
            }
            document.assignments.forEach { assignment ->
                Column {
                    Text(
                        if (assignment.type == "individual") "Cá nhân" else assignment.departmentName,
                        style = MaterialTheme.typography.labelLarge,
                    )
                    if (assignment.content.isNotBlank()) {
                        Text(assignment.content, style = MaterialTheme.typography.bodySmall)
                    }
                    Text(
                        "Hạn ${assignment.deadline} · ${assignment.taskCount ?: assignment.members.size} người",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            WorkApprovalProgressBlock(document)
            WorkDecisionButtons(document, busy, onDecide, modifier = Modifier.padding(top = 4.dp))
        }
    }
}

/** Confirm approval (irreversible lock) or return with a required reason. */
@Composable
internal fun WorkDecisionDialog(
    request: WorkDecisionRequest,
    busy: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (reason: String?) -> Unit,
) {
    var reason by remember(request) { mutableStateOf("") }
    var error by remember(request) { mutableStateOf<String?>(null) }
    val returning = !request.approve
    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(if (returning) "Trả lại công việc" else "Duyệt công việc") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(workListTitle(request.document), style = MaterialTheme.typography.titleSmall)
                Text(
                    buildString {
                        append(WorkApprovalPolicy.creatorLabel(request.document))
                        WorkApprovalPolicy.formatDateTime(request.document.submittedAt).takeIf { it.isNotEmpty() }
                            ?.let { append(" · gửi lúc $it") }
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (returning) {
                    OutlinedTextField(
                        value = reason,
                        onValueChange = {
                            reason = it.take(WorkApprovalPolicy.RETURN_REASON_MAX_LENGTH)
                            error = null
                        },
                        label = { Text("Lý do trả lại (bắt buộc)") },
                        supportingText = {
                            Text(error ?: "${reason.trim().length}/${WorkApprovalPolicy.RETURN_REASON_MAX_LENGTH}")
                        },
                        isError = error != null,
                        minLines = 3,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text("Người tạo sẽ sửa và gửi duyệt lại.", style = MaterialTheme.typography.bodySmall)
                } else {
                    Text(
                        "Sau khi bạn duyệt, công việc không thể sửa hoặc xóa nữa. Khi đủ người duyệt, công việc được giao ngay cho người nhận.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                enabled = !busy,
                onClick = {
                    if (returning) {
                        val problem = WorkApprovalPolicy.validateReturnReason(reason)
                        if (problem != null) {
                            error = problem
                            return@Button
                        }
                        onConfirm(reason.trim())
                    } else {
                        onConfirm(null)
                    }
                },
                colors = if (returning) {
                    ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                } else {
                    ButtonDefaults.buttonColors()
                },
            ) { Text(if (returning) "Trả lại" else "Duyệt") }
        },
        dismissButton = {
            TextButton(enabled = !busy, onClick = onDismiss) { Text("Đóng") }
        },
    )
}

/** Lazy rows of the "Chờ tôi duyệt" section (heading, awaiting, history toggle, history). */
internal fun workApprovalQueueRowCount(state: WorkUiState, showDecided: Boolean): Int {
    if (state.approvalQueue.isEmpty()) return 0
    val awaitingRows = state.awaitingApprovals.size.coerceAtLeast(1)
    val historyRows = if (state.decidedApprovals.isEmpty()) 0 else 1 + if (showDecided) state.decidedApprovals.size else 0
    return 1 + awaitingRows + historyRows
}

/** Index of [focusId] among the queue rows, or -1. */
internal fun workApprovalQueueFocusIndex(state: WorkUiState, showDecided: Boolean, focusId: String?): Int {
    if (focusId.isNullOrBlank() || state.approvalQueue.isEmpty()) return -1
    val awaiting = state.awaitingApprovals.indexOfFirst { it.id == focusId }
    if (awaiting >= 0) return 1 + awaiting
    if (!showDecided) return -1
    val decided = state.decidedApprovals.indexOfFirst { it.id == focusId }
    if (decided < 0) return -1
    return 1 + state.awaitingApprovals.size.coerceAtLeast(1) + 1 + decided
}

internal fun LazyListScope.workApprovalQueueItems(
    state: WorkUiState,
    focusId: String?,
    showDecided: Boolean,
    onToggleDecided: () -> Unit,
    onOpen: (WorkApprovalItem) -> Unit,
    onOpenFile: (WorkApprovalItem) -> Unit,
    onDecide: (WorkDecisionRequest) -> Unit,
) {
    if (state.approvalQueue.isEmpty()) return
    item(key = "approval-queue-heading") {
        Text("Chờ tôi duyệt", style = MaterialTheme.typography.titleLarge)
    }
    if (state.awaitingApprovals.isEmpty()) {
        item(key = "approval-queue-empty") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Không có công việc chờ bạn duyệt", style = MaterialTheme.typography.titleSmall)
                Text(
                    "Khi Văn thư/Quản trị gửi công việc cần Ban giám hiệu duyệt, công việc sẽ xuất hiện tại đây.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    } else {
        items(state.awaitingApprovals, key = { "approval-queue-${it.id}" }) { document ->
            WorkApprovalQueueCard(
                document = document,
                focused = document.id == focusId,
                busy = state.busyApprovalId != null,
                onOpen = { onOpen(document) },
                onOpenFile = { onOpenFile(document) },
                onDecide = onDecide,
            )
        }
    }
    if (state.decidedApprovals.isNotEmpty()) {
        item(key = "approval-queue-history") {
            TextButton(onClick = onToggleDecided) {
                Text(
                    "${if (showDecided) "Ẩn" else "Xem"} đã xử lý trong 30 ngày (${state.decidedApprovals.size})",
                )
            }
        }
        if (showDecided) {
            items(state.decidedApprovals, key = { "approval-history-${it.id}" }) { document ->
                WorkApprovalQueueCard(
                    document = document,
                    focused = document.id == focusId,
                    busy = state.busyApprovalId != null,
                    onOpen = { onOpen(document) },
                    onOpenFile = { onOpenFile(document) },
                    onDecide = onDecide,
                )
            }
        }
    }
}

/** Muted "Đã chỉnh sửa bởi … lúc HH:mm dd/MM/yyyy" when the server reports a later edit. */
@Composable
internal fun WorkLastEditedLine(document: WorkApprovalItem, modifier: Modifier = Modifier) {
    val line = WorkDocumentActions.lastEditedLine(document) ?: return
    Text(
        line,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier,
    )
}

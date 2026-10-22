package lvt.crm.ui.work

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TextButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import lvt.crm.data.work.WorkApprovalItem
import lvt.crm.data.work.WorkApprovalPolicy
import lvt.crm.data.work.WorkTaskItem
import lvt.crm.data.work.needsCompletion
import lvt.crm.ui.components.LvtScreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkDocumentDetailScreen(
    document: WorkApprovalItem,
    onBack: () -> Unit,
    onOpenFile: () -> Unit,
    onChat: () -> Unit,
    busy: Boolean = false,
    onDecide: ((WorkDecisionRequest) -> Unit)? = null,
) {
    BackHandler(onBack = onBack)
    val grouped = document.assignments.groupBy { it.departmentName.ifBlank { "Khác" } }
        .toSortedMap()
    val unreleased = WorkApprovalPolicy.isUnreleased(document)
    LvtScreen(
        title = "Chi tiết công việc",
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại")
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 28.dp),
        ) {
            ListItem(
                headlineContent = {
                    Text(workListTitle(document))
                },
                supportingContent = {
                    val body = buildList {
                        workListSubtitle(document)?.let(::add)
                        if (document.creatorName.isNotBlank()) add(WorkApprovalPolicy.creatorLabel(document))
                        WorkApprovalPolicy.formatDateTime(document.submittedAt).takeIf {
                            it.isNotEmpty() && WorkApprovalPolicy.followsApproval(document)
                        }?.let { add("Gửi duyệt lúc $it") }
                        add("Hạn: ${document.deadline}")
                    }
                    Text(body.joinToString("\n"))
                },
                leadingContent = {
                    Icon(Icons.Outlined.Description, contentDescription = null)
                },
                modifier = Modifier.clickable(enabled = document.fileName.isNotBlank(), onClick = onOpenFile),
            )
            if (WorkApprovalPolicy.followsApproval(document)) {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    WorkDocumentStatusPill(document)
                }
                WorkApprovalProgressBlock(
                    document,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
            if (onDecide != null) {
                WorkDecisionButtons(
                    document = document,
                    busy = busy,
                    onDecide = onDecide,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
            if (document.fileName.isNotBlank()) {
                Button(
                    onClick = onOpenFile,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    Text("Mở tệp")
                }
            }
            TextButton(
                onClick = onChat,
                modifier = Modifier.padding(horizontal = 16.dp),
            ) {
                Text("Trao đổi")
            }
            grouped.forEach { (department, assignments) ->
                HorizontalDivider()
                Text(
                    department,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
                assignments.forEach { assignment ->
                    val members = if (unreleased) {
                        assignment.members.joinToString(", ") { it.name }
                    } else {
                        assignment.members.joinToString("\n") { member ->
                            "${member.name}: ${workStatusLabel(member.status)}"
                        }
                    }
                    ListItem(
                        headlineContent = { Text(assignment.content.ifBlank { department }) },
                        supportingContent = {
                            Text(
                                buildList {
                                    if (unreleased) add(WorkApprovalPolicy.UNRELEASED_LABEL)
                                    add("Hạn: ${assignment.deadline}")
                                    assignment.taskCount?.takeIf { assignment.members.isEmpty() }
                                        ?.let { add("$it người") }
                                    if (members.isNotBlank()) add(members)
                                }.joinToString("\n"),
                            )
                        },
                        leadingContent = {
                            Icon(Icons.Outlined.Groups, contentDescription = null)
                        },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkTaskDetailScreen(
    task: WorkTaskItem,
    busy: Boolean,
    onBack: () -> Unit,
    onComplete: () -> Unit,
    onOpenFile: (() -> Unit)? = null,
    onChat: (() -> Unit)? = null,
) {
    BackHandler(onBack = onBack)
    LvtScreen(
        title = "Chi tiết nhiệm vụ",
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại")
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(task.title, style = MaterialTheme.typography.headlineSmall)
            Text(
                workStatusLabel(task),
                style = MaterialTheme.typography.titleMedium,
                color = when (workStatusTone(task.status)) {
                    lvt.crm.ui.components.StatusTone.Positive -> MaterialTheme.colorScheme.primary
                    lvt.crm.ui.components.StatusTone.Warning -> MaterialTheme.colorScheme.error
                    else -> MaterialTheme.colorScheme.secondary
                },
            )
            if (task.documentContent.isNotBlank()) {
                Text(task.documentContent, style = MaterialTheme.typography.bodyLarge)
            }
            if (task.departmentName.isNotBlank()) {
                Text("Đơn vị: ${task.departmentName}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("Hạn: ${task.deadline}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (task.hasAttachedFile()) {
                Text(
                    "Tệp đính kèm: ${task.fileName.ifBlank { "Công văn đính kèm" }}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = { onOpenFile?.invoke() },
                    enabled = onOpenFile != null,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Mở tệp đính kèm")
                }
            }
            task.qualityPercent?.let {
                Text("Chất lượng: $it%", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (task.note.isNotBlank()) {
                Text(
                    "Nội dung đã gửi người giao: ${task.note}",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (task.rejectionReason.isNotBlank()) {
                Text(
                    "Lý do từ chối: ${task.rejectionReason}",
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (onChat != null) {
                TextButton(onClick = onChat, modifier = Modifier.fillMaxWidth()) {
                    Text("Trao đổi")
                }
            }
            if (needsCompletion(task.status)) {
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = onComplete,
                    enabled = !busy,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(if (busy) "Đang xử lý…" else "Hoàn thành")
                }
            }
        }
    }
}

package lvt.crm.ui.work

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AssignmentLate
import androidx.compose.material.icons.outlined.Business
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CheckCircleOutline
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.HourglassTop
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.PersonOutline
import androidx.compose.material.icons.outlined.PendingActions
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.activity.compose.BackHandler
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import lvt.crm.data.work.WorkTaskItem
import lvt.crm.data.chat.ChatRepository
import lvt.crm.data.chat.ChatTarget
import lvt.crm.data.chat.workChatTarget
import lvt.crm.data.work.WorkApprovalItem
import lvt.crm.data.work.WorkApprovalPolicy
import lvt.crm.data.work.WorkDocumentActions
import lvt.crm.ui.chat.ChatDialog
import lvt.crm.data.work.WorkCompletionReviewItem
import lvt.crm.data.work.WorkDocumentAssignment
import lvt.crm.data.work.needsCompletion
import lvt.crm.ui.components.IconTabBar
import lvt.crm.ui.components.IconTabItem
import lvt.crm.ui.components.ListSearchBar
import lvt.crm.ui.components.ListSearchState
import lvt.crm.ui.components.LvtScreen
import lvt.crm.ui.components.StatePanel
import lvt.crm.ui.components.StatusPill
import lvt.crm.ui.components.StatusTone
import lvt.crm.ui.components.GuideAnchors

@Composable
fun WorkScreen(
    viewModel: WorkViewModel,
    chatRepository: ChatRepository,
    focusId: String?,
    openChat: Boolean = false,
    focusToken: String? = null,
    tabOpenToken: Int,
    openFilter: WorkDashboardFilter? = null,
    openFilterToken: Int = 0,
    onOpenDocument: (WorkApprovalItem) -> Unit = {},
) {
    val state by viewModel.uiState.collectAsState()
    var chatTarget by remember { mutableStateOf<ChatTarget?>(null) }
    var editingDocument by remember { mutableStateOf<WorkApprovalItem?>(null) }
    var consumedChatToken by remember { mutableStateOf<String?>(null) }
    var decision by remember { mutableStateOf<WorkDecisionRequest?>(null) }
    LaunchedEffect(focusToken, openChat, focusId, state.loading, state.tasks, state.approvals, state.approvalQueue) {
        if (!openChat || focusId.isNullOrBlank() || focusToken.isNullOrBlank()) return@LaunchedEffect
        if (state.loading && state.tasks.isEmpty() && state.approvals.isEmpty()) return@LaunchedEffect
        if (consumedChatToken == focusToken) return@LaunchedEffect
        consumedChatToken = focusToken
        chatTarget = workChatTarget(focusId, state.tasks, state.approvals + state.approvalQueue)
    }
    decision?.let { request ->
        WorkDecisionDialog(
            request = request,
            busy = state.busyApprovalId != null,
            onDismiss = { decision = null },
            onConfirm = { reason ->
                if (viewModel.decideApproval(request.document, request.approve, reason)) decision = null
            },
        )
    }
    val onDecide: (WorkDecisionRequest) -> Unit = { decision = it }
    chatTarget?.let { target ->
        ChatDialog(
            repository = chatRepository,
            target = target,
            onBack = { chatTarget = null },
        )
    }
    val openThread: (ChatTarget) -> Unit = { chatTarget = it }
    val context = LocalContext.current
    var showingCreate by rememberSaveable { mutableStateOf(false) }
    var evidenceFile by remember { mutableStateOf<WorkPickedFile?>(null) }
    var evidenceTypeId by remember { mutableStateOf("") }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia(),
    ) { uri: Uri? ->
        val task = state.evidencePromptTask
        if (uri != null && task != null) {
            val picked = readWorkAttachment(context, uri)
            if (picked.error != null) {
                viewModel.setActionError(picked.error)
            } else {
                evidenceFile = picked.file
                evidenceTypeId = ""
            }
        }
    }

    val documentPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        val task = state.evidencePromptTask
        if (uri != null && task != null) {
            val picked = readWorkAttachment(context, uri)
            if (picked.error != null) {
                viewModel.setActionError(picked.error)
            } else {
                evidenceFile = picked.file
                evidenceTypeId = ""
            }
        }
    }

    LaunchedEffect(state.evidencePromptTask?.id) {
        if (state.evidencePromptTask == null) {
            evidenceFile = null
            evidenceTypeId = ""
        }
    }

    LaunchedEffect(openFilterToken) {
        if (openFilterToken == 0) return@LaunchedEffect
        if (openFilter == null) {
            viewModel.setMineTab(WorkListTab.Todo)
        } else {
            viewModel.applyDashboardFilter(openFilter)
        }
    }

    if (state.canCreate && (showingCreate || editingDocument != null)) {
        WorkCreateScreen(
            viewModel = viewModel,
            editing = editingDocument,
            onBack = {
                showingCreate = false
                editingDocument = null
            },
            onCreated = {
                showingCreate = false
                editingDocument = null
            },
        )
        return
    }

    if (state.canCreate) {
        AdminWorkScreen(
            state = state,
            focusId = focusId,
            onRefresh = viewModel::refresh,
            onReview = viewModel::reviewCompletion,
            onOpenDocument = onOpenDocument,
            onMineTab = viewModel::setMineTab,
            onCreatedTab = viewModel::setCreatedTab,
            onSearchChange = viewModel::updateSearch,
            onCompleteTask = { task -> viewModel.requestComplete(task) },
            onCreate = { showingCreate = true },
            onEdit = { editingDocument = it },
            onDelete = { viewModel.deleteDocument(it.id) },
            openChat = openChat,
            onOpenChat = openThread,
            onDecide = onDecide,
        )
    } else {
        val listState = rememberLazyListState()
        var selectedApprovalId by rememberSaveable { mutableStateOf<String?>(null) }
        var selectedTaskId by rememberSaveable { mutableStateOf<String?>(null) }
        var missingFocus by remember { mutableStateOf(false) }
        var consumedFocusId by remember { mutableStateOf<String?>(null) }
        var showDecided by rememberSaveable { mutableStateOf(false) }
        val visibleApprovals = state.awaitingApprovals + if (showDecided) state.decidedApprovals else emptyList()
        val visibleTasks = state.visibleMine
        val selectedApproval = state.approvalQueue.firstOrNull { it.id == selectedApprovalId }
        val selectedTask = state.tasks.firstOrNull { it.id == selectedTaskId }

        BackHandler(enabled = selectedApprovalId != null || selectedTaskId != null) {
            selectedApprovalId = null
            selectedTaskId = null
        }
        LaunchedEffect(focusId, state.loading, state.approvals, state.tasks) {
            if (focusId.isNullOrBlank() || state.loading || consumedFocusId == focusId) return@LaunchedEffect
            consumedFocusId = focusId
            val approval = state.approvalQueue.firstOrNull { it.id == focusId }
            val task = state.tasks.firstOrNull { it.id == focusId || it.documentId == focusId }
            when {
                approval != null -> selectedApprovalId = approval.id
                task != null -> selectedTaskId = task.id
                openChat -> Unit
                else -> missingFocus = true
            }
        }

        LaunchedEffect(focusId, visibleApprovals, visibleTasks) {
            val approvalIndex = workApprovalQueueFocusIndex(state, showDecided, focusId)
            if (approvalIndex >= 0) {
                listState.animateScrollToItem(approvalIndex)
                return@LaunchedEffect
            }
            val taskIndex = visibleTasks.indexOfFirst { it.id == focusId || it.documentId == focusId }
            if (taskIndex >= 0) {
                // Queue rows, then the "Việc được giao" heading.
                listState.animateScrollToItem(workApprovalQueueRowCount(state, showDecided) + 1 + taskIndex)
            }
        }
        LaunchedEffect(tabOpenToken) {
            if (visibleApprovals.isNotEmpty() || visibleTasks.isNotEmpty()) listState.scrollToItem(0)
        }

        if (missingFocus) {
            AlertDialog(
                onDismissRequest = { missingFocus = false },
                title = { Text("Không tìm thấy công việc") },
                text = { Text("Mục này không còn tồn tại hoặc bạn không có quyền xem.") },
                confirmButton = {
                    TextButton(onClick = { missingFocus = false }) { Text("Đóng") }
                },
            )
        }

        selectedApproval?.let { document ->
            WorkDocumentDetailScreen(
                document = document,
                onBack = { selectedApprovalId = null },
                onOpenFile = { onOpenDocument(document) },
                onChat = { openThread(workChatTarget(document.id, state.tasks, listOf(document))) },
                busy = state.busyApprovalId != null,
                onDecide = onDecide,
            )
        } ?: selectedTask?.let { task ->
            WorkTaskDetailScreen(
                task = task,
                busy = state.busyTaskId != null,
                onBack = { selectedTaskId = null },
                onComplete = { viewModel.requestComplete(task) },
                onOpenFile = if (task.hasAttachedFile()) {
                    { onOpenDocument(task.toAttachedDocument()) }
                } else {
                    null
                },
                onChat = task.documentId.takeIf { it.isNotBlank() }?.let { documentId ->
                    { openThread(workChatTarget(documentId, listOf(task), emptyList())) }
                },
            )
        } ?: LvtScreen(
            title = "Công việc",
            helpAnchor = GuideAnchors.WORK,
            refreshing = state.refreshing,
            onRefresh = { viewModel.refresh() },
            showAccountHeader = true,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp),
            ) {
            when {
                state.loading -> {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        CircularProgressIndicator()
                        Text(
                            "Đang tải công việc…",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 14.dp),
                        )
                    }
                }
                state.error != null -> {
                    StatePanel(
                        icon = Icons.Outlined.WarningAmber,
                        title = "Chưa tải được công việc",
                        message = state.error.orEmpty(),
                        action = {
                            Button(onClick = { viewModel.refresh(initial = true) }) {
                                Text("Thử lại")
                            }
                        },
                    )
                }
                else -> {
                    state.actionError?.let {
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.errorContainer,
                            ),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(bottom = 10.dp),
                        ) {
                            Text(
                                it,
                                color = MaterialTheme.colorScheme.onErrorContainer,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(12.dp),
                            )
                        }
                    }
                    ListSearchBar(
                        value = state.search,
                        onChange = viewModel::updateSearch,
                        queryPlaceholder = "Tìm theo tên hoặc nội dung công việc",
                        personPlaceholder = "Tên người được giao",
                        showLocation = false,
                        modifier = Modifier.padding(bottom = 12.dp),
                    )
                    state.notice?.let { message ->
                        Text(
                            message,
                            color = MaterialTheme.colorScheme.primary,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(bottom = 8.dp),
                        )
                    }
                    LazyColumn(
                        modifier = Modifier.weight(1f),
                        state = listState,
                        contentPadding = PaddingValues(bottom = 28.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        workApprovalQueueItems(
                            state = state,
                            focusId = focusId,
                            showDecided = showDecided,
                            onToggleDecided = { showDecided = !showDecided },
                            onOpen = { selectedApprovalId = it.id },
                            onOpenFile = onOpenDocument,
                            onDecide = onDecide,
                        )
                        item(key = "mine-heading") {
                            WorkListSectionHeader(
                                title = "Việc được giao",
                                tab = state.mineTab,
                                onTab = viewModel::setMineTab,
                                counts = state.mineTabCounts,
                            )
                        }
                        if (state.visibleMine.isEmpty()) {
                            item(key = "mine-empty") {
                                WorkListEmpty(
                                    tab = state.mineTab,
                                    created = false,
                                    needsExecutionOnly = state.needsExecutionOnly,
                                    filtered = state.mineSearchEmpty,
                                )
                            }
                        } else {
                            items(state.visibleMine, key = { "${it.kind}-${it.id}" }) { task ->
                                WorkCard(
                                    task = task,
                                    focused = task.id == focusId || task.documentId == focusId,
                                    busy = state.busyTaskId != null || state.busyApprovalId != null,
                                    onOpen = { selectedTaskId = task.id },
                                    onComplete = { viewModel.requestComplete(task) },
                                    onChat = task.documentId.takeIf { it.isNotBlank() }?.let { documentId ->
                                        { openThread(workChatTarget(documentId, listOf(task), emptyList())) }
                                    },
                                )
                            }
                        }
                    }
                }
            }
            }
        }

    }

    val prompt = state.qualityPromptTask
    if (prompt != null) {
        AlertDialog(
            onDismissRequest = viewModel::dismissQualityPrompt,
            icon = {
                Icon(Icons.Outlined.TaskAlt, contentDescription = null)
            },
            title = { Text("Ghi nhận chất lượng") },
            text = {
                Column {
                    Text(
                        "Nhập tỷ lệ chất lượng hoàn thành cho công việc “${prompt.title}”.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(modifier = Modifier.height(14.dp))
                    OutlinedTextField(
                        value = state.qualityInput,
                        onValueChange = viewModel::onQualityInput,
                        label = { Text("% chất lượng") },
                        supportingText = { Text("Giá trị từ 0 đến 100") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.medium,
                    )
                }
            },
            confirmButton = {
                Button(onClick = viewModel::confirmQualityComplete) {
                    Text("Xác nhận")
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissQualityPrompt) {
                    Text("Hủy")
                }
            },
            shape = MaterialTheme.shapes.large,
        )
    }

    state.evidencePromptTask?.let { task ->
        val requireType = task.kind == WorkTaskItem.Kind.WorkItem
        AlertDialog(
            onDismissRequest = viewModel::dismissEvidencePrompt,
            title = { Text("Nộp bằng chứng hoàn thành") },
            text = {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 420.dp)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        "Chọn tài liệu hoặc hình ảnh bằng chứng hoàn thành công việc “${task.title}” (tối đa 20MB). Có thể gửi thêm nội dung cho người giao.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    OutlinedTextField(
                        value = state.evidenceNote,
                        onValueChange = viewModel::onEvidenceNoteChange,
                        label = { Text("Nội dung gửi người giao (không bắt buộc)") },
                        supportingText = { Text("${state.evidenceNote.trim().length}/500") },
                        minLines = 3,
                        maxLines = 5,
                        modifier = Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.medium,
                    )
                    OutlinedButton(
                        onClick = {
                            photoPickerLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Outlined.Image, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Chọn từ Thư viện ảnh")
                    }
                    OutlinedButton(
                        onClick = {
                            documentPickerLauncher.launch(
                                arrayOf(
                                    "application/pdf",
                                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                    "application/vnd.ms-excel",
                                    "image/*",
                                )
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Icon(Icons.Outlined.Description, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Chọn từ Tệp (PDF, Word, Excel)")
                    }
                    evidenceFile?.let { file ->
                        Text(file.fileName, style = MaterialTheme.typography.bodyMedium)
                        if (requireType) {
                            WorkDocumentTypeField(
                                types = state.documentTypes,
                                selectedId = evidenceTypeId,
                                onSelect = { evidenceTypeId = it },
                            )
                        }
                    }
                }
            },
            confirmButton = {
                val file = evidenceFile
                Button(
                    onClick = {
                        if (file == null) {
                            viewModel.setActionError("Vui lòng đính kèm file bằng chứng hoàn thành.")
                            return@Button
                        }
                        viewModel.completeWithEvidence(
                            task,
                            file.bytes,
                            file.fileName,
                            file.mimeType,
                            evidenceTypeId,
                        )
                    },
                    enabled = file != null && (!requireType || evidenceTypeId.isNotBlank()),
                ) {
                    Text("Nộp")
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissEvidencePrompt) {
                    Text("Hủy")
                }
            },
            shape = MaterialTheme.shapes.large,
        )
    }
}

private val ALLOWED_EXTENSIONS = setOf("pdf", "docx", "xlsx", "xls", "png", "jpg", "jpeg")
private const val MAX_FILE_SIZE = 20 * 1024 * 1024 // 20 MB

internal data class WorkPickedFile(
    val bytes: ByteArray,
    val fileName: String,
    val mimeType: String,
)

internal data class WorkPickedFileResult(
    val file: WorkPickedFile? = null,
    val error: String? = null,
)

internal fun readWorkAttachment(context: Context, uri: Uri): WorkPickedFileResult {
    return try {
        var fileName = "tep_dinh_kem"
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst()) {
                if (nameIndex != -1) cursor.getString(nameIndex)?.takeIf { it.isNotBlank() }?.let { fileName = it }
            }
        }
        val ext = fileName.substringAfterLast('.', "").lowercase()
        if (ext !in ALLOWED_EXTENSIONS) {
            return WorkPickedFileResult(error = "Chỉ chấp nhận tệp PDF, DOCX, Excel, PNG hoặc JPG.")
        }
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        if (bytes == null || bytes.isEmpty()) {
            return WorkPickedFileResult(error = "Tệp rỗng hoặc không đọc được. Vui lòng thử lại.")
        }
        if (bytes.size > MAX_FILE_SIZE) {
            return WorkPickedFileResult(error = "Dung lượng tệp tối đa là 20MB.")
        }
        val mimeType = context.contentResolver.getType(uri)?.takeIf { it.isNotBlank() }
            ?: when (ext) {
                "pdf" -> "application/pdf"
                "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                "xls" -> "application/vnd.ms-excel"
                "png" -> "image/png"
                "jpg", "jpeg" -> "image/jpeg"
                else -> "application/octet-stream"
            }
        WorkPickedFileResult(file = WorkPickedFile(bytes, fileName, mimeType))
    } catch (_: Exception) {
        WorkPickedFileResult(error = "Không thể đọc tệp đã chọn. Vui lòng thử lại.")
    }
}

internal enum class AdminDocumentFilter { All, Pending, Approved, PendingCompletion }

@Composable
private fun AdminWorkScreen(
    state: WorkUiState,
    focusId: String?,
    onRefresh: () -> Unit,
    onReview: (WorkCompletionReviewItem, Boolean, Int?, String?) -> Unit,
    onOpenDocument: (WorkApprovalItem) -> Unit,
    onMineTab: (WorkListTab) -> Unit,
    onCreatedTab: (WorkListTab) -> Unit,
    onSearchChange: (ListSearchState) -> Unit,
    onCompleteTask: (WorkTaskItem) -> Unit,
    onCreate: () -> Unit,
    onEdit: (WorkApprovalItem) -> Unit,
    onDelete: (WorkApprovalItem) -> Unit,
    openChat: Boolean = false,
    onOpenChat: (ChatTarget) -> Unit = {},
    onDecide: (WorkDecisionRequest) -> Unit = {},
) {
    var selectedDocumentId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedQueueId by rememberSaveable { mutableStateOf<String?>(null) }
    var showDecided by rememberSaveable { mutableStateOf(false) }
    val selectedQueueDocument = state.approvalQueue.firstOrNull { it.id == selectedQueueId }
    var pendingDelete by remember { mutableStateOf<WorkApprovalItem?>(null) }
    val selectedDocument = currentAdminDocument(state.approvals, selectedDocumentId)
    var selectedTaskId by rememberSaveable { mutableStateOf<String?>(null) }
    val selectedTask = state.tasks.firstOrNull { it.id == selectedTaskId }
    var selectedReview by remember { mutableStateOf<WorkCompletionReviewItem?>(null) }
    var qualityPercent by rememberSaveable { mutableStateOf("100") }
    var rejectionReason by rememberSaveable { mutableStateOf("") }
    val pendingReviews = state.completionReviews.associateBy { it.workItemId + it.userId }
    val documents = state.visibleCreated

    BackHandler(enabled = (selectedDocumentId != null || selectedTaskId != null) && selectedReview == null) {
        selectedDocumentId = null
        selectedTaskId = null
    }
    LaunchedEffect(focusId, state.approvals, state.approvalQueue, state.tasks, state.completionReviews, state.loading, openChat) {
        if (focusId.isNullOrBlank() || state.loading) return@LaunchedEffect
        val review = state.completionReviews.firstOrNull { it.workItemId == focusId }
        val focusedDocument = focusedAdminDocument(state.approvals, focusId)
        val queued = state.approvalQueue.firstOrNull { it.id == focusId }
        val task = state.tasks.firstOrNull { it.id == focusId || it.documentId == focusId }
        when {
            // "Công việc chờ duyệt" → the approver's own queue entry.
            queued != null && !openChat -> selectedQueueId = queued.id
            focusedDocument != null && focusedDocument.id == focusId -> selectedDocumentId = focusedDocument.id
            task != null -> selectedTaskId = task.id
            review != null && !openChat -> selectedReview = review
            focusedDocument != null -> selectedDocumentId = focusedDocument.id
        }
    }
    LaunchedEffect(selectedDocumentId, selectedDocument) {
        if (selectedDocumentId != null && selectedDocument == null && !state.loading) {
            selectedDocumentId = null
        }
    }

    selectedQueueDocument?.let { document ->
        WorkDocumentDetailScreen(
            document = document,
            onBack = { selectedQueueId = null },
            onOpenFile = { onOpenDocument(document) },
            onChat = { onOpenChat(workChatTarget(document.id, state.tasks, listOf(document))) },
            busy = state.busyApprovalId != null,
            onDecide = onDecide,
        )
        return
    }

    Column(modifier = Modifier.fillMaxSize()) {
        LvtScreen(
            title = when {
                selectedDocument != null -> "Chi tiết công việc"
                selectedTask != null -> "Chi tiết công việc"
                else -> "Công việc"
            },
            refreshing = state.refreshing,
            onRefresh = onRefresh,
            navigationIcon = if (selectedDocument != null || selectedTask != null) {
                {
                    IconButton(onClick = {
                        selectedDocumentId = null
                        selectedTaskId = null
                    }) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Quay lại")
                    }
                }
            } else {
                null
            },
            showAccountHeader = selectedDocument == null && selectedTask == null,
            helpAnchor = GuideAnchors.WORK.takeIf { selectedDocument == null && selectedTask == null },
            actions = {
                if (selectedDocument == null && selectedTask == null) {
                    TextButton(onClick = onCreate) { Text("Tạo") }
                }
            },
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp),
            ) {
        when {
            state.loading -> LoadingWorkPanel()
            state.error != null -> WorkLoadError(state.error.orEmpty(), onRefresh)
            selectedTask != null -> {
                WorkTaskDetailScreen(
                    task = selectedTask,
                    busy = state.busyTaskId != null,
                    onBack = { selectedTaskId = null },
                    onComplete = { onCompleteTask(selectedTask) },
                    onOpenFile = if (selectedTask.hasAttachedFile()) {
                        { onOpenDocument(selectedTask.toAttachedDocument()) }
                    } else {
                        null
                    },
                    onChat = selectedTask.documentId.takeIf { it.isNotBlank() }?.let { documentId ->
                        { onOpenChat(workChatTarget(documentId, listOf(selectedTask), emptyList())) }
                    },
                )
            }
            selectedDocument == null -> {
                ListSearchBar(
                    value = state.search,
                    onChange = onSearchChange,
                    queryPlaceholder = "Tìm theo tên hoặc nội dung công việc",
                    personPlaceholder = "Tên người được giao",
                    showLocation = false,
                    modifier = Modifier.padding(bottom = 12.dp),
                )
                state.notice?.let { message ->
                    Text(
                        message,
                        color = MaterialTheme.colorScheme.primary,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.padding(bottom = 8.dp),
                    )
                }
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(bottom = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    workApprovalQueueItems(
                        state = state,
                        focusId = focusId,
                        showDecided = showDecided,
                        onToggleDecided = { showDecided = !showDecided },
                        onOpen = { selectedQueueId = it.id },
                        onOpenFile = onOpenDocument,
                        onDecide = onDecide,
                    )
                    if (state.completionReviews.isNotEmpty()) {
                        item(key = "reviews-heading") {
                            Text("Duyệt hoàn thành", style = MaterialTheme.typography.titleLarge)
                        }
                        items(state.completionReviews, key = { "review-${it.workItemId}-${it.userId}" }) { review ->
                            Card(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { selectedReview = review },
                                colors = CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = .62f),
                                ),
                            ) {
                                Column(modifier = Modifier.padding(16.dp)) {
                                    Text(review.content, style = MaterialTheme.typography.titleSmall)
                                    Text(
                                        "${review.userName} · hạn ${review.deadline}",
                                        style = MaterialTheme.typography.bodySmall,
                                    )
                                    if (review.note.isNotBlank()) {
                                        Text(
                                            review.note,
                                            style = MaterialTheme.typography.bodySmall,
                                            modifier = Modifier.padding(top = 6.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }
                    item(key = "mine-heading") {
                        WorkListSectionHeader(
                            title = "Việc được giao",
                            tab = state.mineTab,
                            onTab = onMineTab,
                            counts = state.mineTabCounts,
                        )
                    }
                    if (state.visibleMine.isEmpty()) {
                        item(key = "mine-empty") {
                            WorkListEmpty(
                                tab = state.mineTab,
                                created = false,
                                needsExecutionOnly = state.needsExecutionOnly,
                                filtered = state.mineSearchEmpty,
                            )
                        }
                    } else {
                        items(state.visibleMine, key = { "mine-${it.kind}-${it.id}" }) { task ->
                            WorkCard(
                                task = task,
                                focused = task.id == focusId || task.documentId == focusId,
                                busy = state.busyTaskId != null,
                                onOpen = { selectedTaskId = task.id },
                                onComplete = { onCompleteTask(task) },
                                onChat = task.documentId.takeIf { it.isNotBlank() }?.let { documentId ->
                                    { onOpenChat(workChatTarget(documentId, listOf(task), emptyList())) }
                                },
                            )
                        }
                    }
                    item(key = "created-heading") {
                        Spacer(modifier = Modifier.height(24.dp))
                        WorkListSectionHeader(
                            title = "Việc tôi tạo",
                            tab = state.createdTab,
                            onTab = onCreatedTab,
                            counts = state.createdTabCounts,
                        )
                    }
                    if (documents.isEmpty()) {
                        item(key = "created-empty") {
                            WorkListEmpty(
                                tab = state.createdTab,
                                created = true,
                                filtered = state.createdSearchEmpty,
                            )
                        }
                    } else {
                        items(documents, key = { "created-${it.id}" }) { document ->
                            AdminDocumentCard(
                                document = document,
                                focused = document.id == focusId,
                                busy = state.creating,
                                onOpen = { selectedDocumentId = document.id },
                                onChat = { onOpenChat(workChatTarget(document.id, state.tasks, listOf(document))) },
                                onEdit = { onEdit(document) },
                                onDelete = { pendingDelete = document },
                            )
                        }
                    }
                }
            }
            else -> {
                val document = selectedDocument ?: return@Column
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(bottom = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item {
                        DocumentSummaryCard(
                            document,
                            busy = state.creating,
                            onOpenDocument = { onOpenDocument(document) },
                            onChat = { onOpenChat(workChatTarget(document.id, state.tasks, listOf(document))) },
                            onEdit = { onEdit(document) },
                            onDelete = { pendingDelete = document },
                        )
                    }
                    if (document.assignments.isEmpty()) {
                        item {
                            StatePanel(
                                icon = Icons.Outlined.TaskAlt,
                                title = "Chưa có công việc được phân công",
                                message = "Công văn này chưa có đầu mục công việc.",
                            )
                        }
                    }
                    document.assignments.groupBy { it.departmentName.ifBlank { "Chưa gán phòng ban" } }
                        .forEach { (departmentName, assignments) ->
                            item(key = "department-$departmentName") {
                                Text(
                                    departmentName.uppercase(),
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.padding(top = 8.dp),
                                )
                            }
                            items(assignments, key = { it.id }) { assignment ->
                                AdminAssignmentCard(
                                    assignment = assignment,
                                    unreleased = WorkApprovalPolicy.isUnreleased(document),
                                    pendingReviews = pendingReviews,
                                    busy = state.busyReviewId != null,
                                    onReview = { review ->
                                        qualityPercent = "100"
                                        rejectionReason = ""
                                        selectedReview = review
                                    },
                                )
                            }
                        }
                }
            }
        }

        state.actionError?.let { message ->
            Text(
                message,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }
            }
        }
    }

    selectedReview?.let { review ->
        val quality = qualityPercent.toIntOrNull()
        AlertDialog(
            onDismissRequest = { selectedReview = null },
            title = { Text("Duyệt hoàn thành") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("${review.userName} · ${review.content}")
                    if (review.note.isNotBlank()) {
                        Text("Nội dung từ người nộp: ${review.note}")
                    }
                    OutlinedTextField(
                        value = qualityPercent,
                        onValueChange = { qualityPercent = it.filter(Char::isDigit).take(3) },
                        label = { Text("% chất lượng khi duyệt") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                    OutlinedTextField(
                        value = rejectionReason,
                        onValueChange = { rejectionReason = it.take(500) },
                        label = { Text("Lý do nếu chưa duyệt") },
                    )
                }
            },
            confirmButton = {
                Button(
                    enabled = quality != null && quality in 0..100,
                    onClick = {
                        selectedReview = null
                        onReview(review, true, quality, null)
                    },
                ) { Text("Duyệt") }
            },
            dismissButton = {
                TextButton(
                    enabled = rejectionReason.isNotBlank(),
                    onClick = {
                        selectedReview = null
                        onReview(review, false, null, rejectionReason)
                    },
                ) { Text("Chưa duyệt") }
            },
        )
    }

    pendingDelete?.let { document ->
        AlertDialog(
            onDismissRequest = { if (!state.creating) pendingDelete = null },
            title = { Text("Xóa công việc ${workListTitle(document)}?") },
            confirmButton = {
                TextButton(
                    enabled = !state.creating,
                    onClick = {
                        val target = document
                        pendingDelete = null
                        if (selectedDocumentId == target.id) selectedDocumentId = null
                        onDelete(target)
                    },
                ) { Text("Xóa") }
            },
            dismissButton = {
                TextButton(enabled = !state.creating, onClick = { pendingDelete = null }) { Text("Hủy") }
            },
        )
    }
}

@Composable
private fun LoadingWorkPanel() {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator()
        Text("Đang tải công việc…", modifier = Modifier.padding(top = 14.dp))
    }
}

@Composable
private fun WorkLoadError(message: String, onRefresh: () -> Unit) {
    StatePanel(
        icon = Icons.Outlined.WarningAmber,
        title = "Chưa tải được công việc",
        message = message,
        action = { Button(onClick = onRefresh) { Text("Thử lại") } },
    )
}

@Composable
private fun AdminDocumentCard(
    document: WorkApprovalItem,
    focused: Boolean,
    busy: Boolean,
    onOpen: () -> Unit,
    onChat: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val displayTitle = workListTitle(document)
    val extension = document.fileName.substringAfterLast('.', "").uppercase().filter { it.isLetterOrDigit() }.take(4)
        .ifBlank { displayTitle.take(2).uppercase().ifBlank { "CV" } }
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = if (focused) {
            BorderStroke(2.dp, MaterialTheme.colorScheme.primary)
        } else {
            BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .7f))
        },
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(MaterialTheme.shapes.medium)
                    .background(
                        if (extension == "PDF") MaterialTheme.colorScheme.errorContainer.copy(alpha = .55f)
                        else MaterialTheme.colorScheme.primaryContainer.copy(alpha = .58f),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    extension,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (extension == "PDF") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                )
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        displayTitle,
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f),
                        maxLines = 2,
                    )
                    WorkDocumentStatusPill(document)
                }
                workListSubtitle(document)?.let { subtitle ->
                    Text(subtitle, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                }
                Text(
                    "Hạn ${document.deadline}  ·  ${document.assignments.size} đầu mục",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text("›", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.outline)
        }
        if (WorkApprovalPolicy.followsApproval(document) && document.status != "approved") {
            WorkApprovalProgressBlock(document, modifier = Modifier.padding(horizontal = 16.dp))
        }
        WorkLastEditedLine(document, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        TextButton(
            onClick = onChat,
            modifier = Modifier.padding(start = 8.dp, bottom = 4.dp),
        ) {
            Text("Trao đổi")
        }
        WorkDocumentActionsRow(document, busy, onEdit, onDelete)
    }
}

@Composable
private fun WorkListSectionHeader(
    title: String,
    tab: WorkListTab,
    onTab: (WorkListTab) -> Unit,
    counts: Map<WorkListTab, Int> = emptyMap(),
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge)
        IconTabBar(
            items = WorkListTab.entries.map { IconTabItem(it.title, it.icon, counts[it] ?: 0) },
            selectedIndex = tab.ordinal,
            onSelect = { index -> onTab(WorkListTab.entries[index]) },
        )
    }
}

private val WorkListTab.icon: ImageVector
    get() = when (this) {
        WorkListTab.Todo -> Icons.Outlined.Inbox
        WorkListTab.PendingReview -> Icons.Outlined.HourglassTop
        WorkListTab.Overdue -> Icons.Outlined.ErrorOutline
        WorkListTab.Completed -> Icons.Outlined.CheckCircle
    }

@Composable
private fun WorkListEmpty(
    tab: WorkListTab,
    created: Boolean,
    needsExecutionOnly: Boolean = false,
    filtered: Boolean = false,
) {
    val message = when {
        filtered -> "Không tìm thấy công việc phù hợp."
        needsExecutionOnly -> "Chưa có công việc cần thực hiện."
        tab == WorkListTab.Completed -> if (created) "Chưa có công việc bạn tạo đã duyệt hoàn thành." else "Chưa có công việc đã duyệt hoàn thành."
        tab == WorkListTab.PendingReview -> if (created) "Không có công việc bạn tạo đang chờ duyệt." else "Không có công việc đang chờ duyệt."
        tab == WorkListTab.Overdue -> if (created) "Chưa có công việc bạn tạo quá hạn." else "Chưa có công việc quá hạn."
        else -> if (created) "Không có việc cần làm trong các công việc bạn tạo." else "Bạn chưa có việc cần làm."
    }
    StatePanel(
        icon = if (filtered) Icons.Outlined.Search else Icons.Outlined.TaskAlt,
        title = if (created) "Việc tôi tạo" else "Việc được giao",
        message = message,
    )
}

@Composable
private fun AdminDocumentTabs(
    selected: AdminDocumentFilter,
    allCount: Int,
    pendingCount: Int,
    approvedCount: Int,
    onSelect: (AdminDocumentFilter) -> Unit,
) {
    val tabs = listOf(
        AdminDocumentFilter.All to "Tất cả ($allCount)",
        AdminDocumentFilter.Pending to "Chờ duyệt ($pendingCount)",
        AdminDocumentFilter.Approved to "Đã duyệt ($approvedCount)",
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        tabs.forEach { (value, label) ->
            FilterChip(
                selected = selected == value,
                onClick = { onSelect(value) },
                label = { Text(label) },
            )
        }
    }
}

internal fun visibleAdminDocuments(
    documents: List<WorkApprovalItem>,
    reviews: List<WorkCompletionReviewItem>,
    filter: AdminDocumentFilter,
): List<WorkApprovalItem> {
    val reviewItemIds = reviews.mapTo(mutableSetOf()) { it.workItemId }
    return documents.filter { document ->
        when (filter) {
            AdminDocumentFilter.All -> true
            AdminDocumentFilter.Pending -> document.status == "pending"
            AdminDocumentFilter.Approved -> document.status == "approved"
            AdminDocumentFilter.PendingCompletion -> document.assignments.any { it.id in reviewItemIds }
        }
    }
}

internal fun currentAdminDocument(
    documents: List<WorkApprovalItem>,
    selectedDocumentId: String?,
): WorkApprovalItem? = documents.firstOrNull { it.id == selectedDocumentId }

internal fun focusedAdminDocument(
    documents: List<WorkApprovalItem>,
    focusId: String?,
): WorkApprovalItem? = documents.firstOrNull { document ->
    document.id == focusId || document.assignments.any { it.id == focusId }
}

@Composable
private fun DocumentSummaryCard(
    document: WorkApprovalItem,
    busy: Boolean,
    onOpenDocument: () -> Unit,
    onChat: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val members = document.assignments.flatMap { it.members }
    val completedCount = members.count { it.status in completedWorkStatuses }
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .7f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(modifier = Modifier.padding(18.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(58.dp)
                    .clip(MaterialTheme.shapes.medium)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.Description,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(31.dp),
                )
            }
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Text(workListTitle(document), style = MaterialTheme.typography.titleMedium, maxLines = 2)
                workListSubtitle(document)?.let { subtitle ->
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        Icons.Outlined.CalendarMonth,
                        contentDescription = null,
                        modifier = Modifier.size(17.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        "Hạn ${document.deadline}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Column(
                modifier = Modifier
                    .clip(MaterialTheme.shapes.medium)
                    .background(
                        if (completedCount == members.size && members.isNotEmpty()) {
                            MaterialTheme.colorScheme.secondaryContainer
                        } else {
                            MaterialTheme.colorScheme.primaryContainer.copy(alpha = .62f)
                        },
                    )
                    .padding(horizontal = 12.dp, vertical = 9.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    "$completedCount/${members.size}",
                    style = MaterialTheme.typography.titleLarge,
                    color = if (completedCount == members.size && members.isNotEmpty()) {
                        MaterialTheme.colorScheme.secondary
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                )
                Text(
                    "hoàn thành",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
            Row(
                modifier = Modifier.padding(top = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                WorkDocumentStatusPill(document)
                if (document.creatorName.isNotBlank()) {
                    Text(
                        WorkApprovalPolicy.creatorLabel(document),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            WorkApprovalProgressBlock(document, modifier = Modifier.padding(top = 10.dp))
            WorkLastEditedLine(document, modifier = Modifier.padding(top = 6.dp))
            if (document.fileName.isNotBlank()) {
                FilledTonalButton(
                    onClick = onOpenDocument,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp),
                ) {
                    Text("Mở tệp")
                }
            }
            TextButton(onClick = onChat, modifier = Modifier.padding(top = 4.dp)) {
                Text("Trao đổi")
            }
            WorkDocumentActionsRow(document, busy, onEdit, onDelete)
        }
    }
}

@Composable
private fun WorkDocumentActionsRow(
    document: WorkApprovalItem,
    busy: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val canEdit = WorkDocumentActions.showsEdit(document)
    val canDelete = WorkDocumentActions.showsDelete(document)
    if (!canEdit && !canDelete) {
        WorkDocumentActions.lockedMessage(document)?.let { message ->
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp),
            )
        }
        return
    }
    Row(
        modifier = Modifier.padding(start = 8.dp, end = 8.dp, bottom = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (canEdit) {
            OutlinedButton(onClick = onEdit, enabled = !busy) { Text("Sửa") }
        }
        if (canDelete) {
            OutlinedButton(onClick = onDelete, enabled = !busy) { Text("Xóa") }
        }
    }
}

@Composable
private fun AdminAssignmentCard(
    assignment: WorkDocumentAssignment,
    unreleased: Boolean,
    pendingReviews: Map<String, WorkCompletionReviewItem>,
    busy: Boolean,
    onReview: (WorkCompletionReviewItem) -> Unit,
) {
    if (unreleased) {
        UnreleasedAssignmentCard(assignment)
        return
    }
    val completedCount = assignment.members.count { it.status in completedWorkStatuses }
    val pendingReviewCount = assignment.members.count { member ->
        pendingReviews.containsKey(assignment.id + member.id)
    }
    val allCompleted = assignment.members.isNotEmpty() && completedCount == assignment.members.size
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .72f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(MaterialTheme.shapes.small)
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .52f))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                Icon(
                    Icons.Outlined.Description,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Text("${assignment.members.size} công việc", style = MaterialTheme.typography.labelLarge)
                Text("·", color = MaterialTheme.colorScheme.outline)
                Icon(
                    Icons.Outlined.CheckCircleOutline,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.size(20.dp),
                )
                Text("$completedCount hoàn thành", style = MaterialTheme.typography.labelLarge)
                if (pendingReviewCount > 0) {
                    Text("·", color = MaterialTheme.colorScheme.outline)
                    Icon(
                        Icons.Outlined.PendingActions,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.tertiary,
                        modifier = Modifier.size(20.dp),
                    )
                    Text("$pendingReviewCount chờ duyệt", style = MaterialTheme.typography.labelLarge)
                }
            }
            Row(
                modifier = Modifier.padding(top = 14.dp, bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Outlined.CalendarMonth,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp),
                )
                Text(
                    "Hạn: ${assignment.deadline}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .7f))
            assignment.members.forEachIndexed { index, member ->
                val review = pendingReviews[assignment.id + member.id]
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 13.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .clip(MaterialTheme.shapes.small)
                            .background(MaterialTheme.colorScheme.primaryContainer.copy(alpha = .58f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Outlined.PersonOutline,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                    Text(member.name, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                    memberStatusPill(member.status)?.let { (label, tone) ->
                        StatusPill(label = label, tone = tone)
                    }
                }
                if (index < assignment.members.lastIndex) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .55f))
                }
            }
            if (pendingReviewCount > 0) {
                val nextReview = assignment.members
                    .mapNotNull { member -> pendingReviews[assignment.id + member.id] }
                    .first()
                Button(
                    onClick = { onReview(nextReview) },
                    enabled = !busy,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 14.dp),
                ) {
                    Icon(Icons.Outlined.PendingActions, contentDescription = null, modifier = Modifier.size(19.dp))
                    Text("Xử lý $pendingReviewCount yêu cầu duyệt", modifier = Modifier.padding(start = 8.dp))
                }
            } else if (allCompleted) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 14.dp)
                        .clip(MaterialTheme.shapes.small)
                        .background(MaterialTheme.colorScheme.secondaryContainer.copy(alpha = .72f))
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.secondary,
                        modifier = Modifier.size(21.dp),
                    )
                    Text(
                        "Hoàn thành $completedCount/${assignment.members.size} công việc",
                        style = MaterialTheme.typography.labelLarge,
                        modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }
        }
    }
}

/** Not handed out yet (waiting for Ban giám hiệu): who will receive it, without progress. */
@Composable
private fun UnreleasedAssignmentCard(assignment: WorkDocumentAssignment) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .72f)),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (assignment.type == "individual") "Cá nhân" else assignment.departmentName,
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                )
                StatusPill(label = WorkApprovalPolicy.UNRELEASED_LABEL, tone = StatusTone.Primary)
            }
            if (assignment.content.isNotBlank()) {
                Text(assignment.content, style = MaterialTheme.typography.bodyMedium)
            }
            Text(
                "Hạn: ${assignment.deadline}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (assignment.members.isNotEmpty()) {
                Text(
                    assignment.members.joinToString(", ") { it.name },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private val completedWorkStatuses = setOf("completed", "approved", "done", "completed_late")

private fun memberStatusPill(status: String): Pair<String, StatusTone>? = when (status) {
    "pending_completion", "pending_approval" -> "Chờ duyệt hoàn thành" to StatusTone.Warning
    "completed", "approved", "done", "completed_late" -> "Đã hoàn thành" to StatusTone.Positive
    "overdue", "rejected_completion", "rejected" -> workStatusLabel(status) to StatusTone.Warning
    else -> null
}

@Composable
private fun WorkFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
    )
}

internal fun orderedWorkApprovals(
    approvals: List<WorkApprovalItem>,
): List<WorkApprovalItem> = approvals.sortedWith(
    compareBy<WorkApprovalItem>(
        { it.myDecision.isNotBlank() },
        { it.deadline },
    ),
)

internal fun visibleWorkApprovals(
    approvals: List<WorkApprovalItem>,
    pendingOnly: Boolean,
): List<WorkApprovalItem> = if (pendingOnly) {
    approvals.filter { it.myDecision.isBlank() }
} else {
    approvals
}

@Composable
private fun WorkCard(
    task: WorkTaskItem,
    focused: Boolean,
    busy: Boolean,
    onOpen: () -> Unit,
    onComplete: () -> Unit,
    onChat: (() -> Unit)? = null,
) {
    val canComplete = needsCompletion(task.status)
    val isRejected = task.status in setOf("rejected", "rejected_completion")
    val isCompleted = task.status in setOf("completed", "approved", "done", "completed_late")
    val accentColor = when {
        isRejected -> MaterialTheme.colorScheme.error
        isCompleted -> MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.primary
    }
    val cardContainerColor = when {
        isRejected -> MaterialTheme.colorScheme.errorContainer
            .copy(alpha = 0.12f)
            .compositeOver(MaterialTheme.colorScheme.surface)
        isCompleted -> MaterialTheme.colorScheme.secondaryContainer
            .copy(alpha = 0.12f)
            .compositeOver(MaterialTheme.colorScheme.surface)
        else -> MaterialTheme.colorScheme.primaryContainer
            .copy(alpha = 0.16f)
            .compositeOver(MaterialTheme.colorScheme.surface)
    }
    val cardBorderColor = if (focused) {
        MaterialTheme.colorScheme.primary
    } else {
        accentColor.copy(alpha = 0.42f)
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 7.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(IntrinsicSize.Max)
                .padding(start = 8.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(
                modifier = Modifier
                    .width(6.dp)
                    .fillMaxHeight()
                    .clip(MaterialTheme.shapes.small)
                    .background(accentColor),
            )
            Card(
                onClick = onOpen,
                modifier = Modifier.weight(1f),
                shape = MaterialTheme.shapes.medium,
                colors = CardDefaults.cardColors(containerColor = cardContainerColor),
                border = BorderStroke(if (focused) 2.dp else 1.dp, cardBorderColor),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
            ) {
                Column(modifier = Modifier.padding(17.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.Top,
                    ) {
                        Row(
                            modifier = Modifier.weight(1f),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(42.dp)
                                    .clip(MaterialTheme.shapes.small)
                                    .background(MaterialTheme.colorScheme.primaryContainer),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(
                                    Icons.Outlined.Description,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                            }
                            Text(
                                task.title.ifBlank { "Công việc" },
                                style = MaterialTheme.typography.titleMedium,
                            )
                        }
                        StatusPill(
                            label = workStatusLabel(task),
                            tone = workStatusTone(task.status),
                        )
                    }
                    if (task.documentContent.isNotBlank() && task.documentContent != task.title) {
                        DetailLine(
                            icon = Icons.Outlined.Description,
                            text = task.documentContent,
                            modifier = Modifier.padding(top = 10.dp),
                        )
                    }
                    DetailLine(
                        icon = Icons.Outlined.CalendarMonth,
                        text = "Hạn ${task.deadline}",
                        modifier = Modifier.padding(top = 8.dp),
                    )
                    if (task.departmentName.isNotBlank()) {
                        DetailLine(
                            icon = Icons.Outlined.Business,
                            text = task.departmentName,
                        )
                    }
                    if (task.note.isNotBlank()) {
                        Text(
                            "Nội dung đã gửi người giao: ${task.note}",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                    if (task.rejectionReason.isNotBlank()) {
                        Card(
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.errorContainer,
                            ),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 10.dp),
                        ) {
                            Row(
                                modifier = Modifier.padding(12.dp),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(
                                    Icons.Outlined.AssignmentLate,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error,
                                )
                                Text(
                                    task.rejectionReason,
                                    color = MaterialTheme.colorScheme.onErrorContainer,
                                    style = MaterialTheme.typography.bodySmall,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                    if (canComplete) {
                        Spacer(modifier = Modifier.height(14.dp))
                        Button(
                            onClick = onComplete,
                            enabled = !busy,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(Icons.Outlined.CheckCircle, contentDescription = null)
                            Text(
                                if (task.isAdmin) "Hoàn thành và chấm %" else "Nộp bằng chứng hoàn thành",
                                modifier = Modifier.padding(start = 7.dp),
                            )
                        }
                    }
                    if (onChat != null) {
                        TextButton(onClick = onChat, modifier = Modifier.padding(top = 4.dp)) {
                            Text("Trao đổi")
                        }
                    }
                }
            }
        }
        Box(
            modifier = Modifier
                .align(Alignment.TopStart)
                .offset(x = (-2).dp, y = (-5).dp)
                .size(31.dp)
                .clip(CircleShape)
                .background(accentColor),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (isCompleted) Icons.Outlined.Check else Icons.Outlined.Star,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun DetailLine(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.padding(vertical = 3.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
    }
}

internal fun workStatusLabel(task: WorkTaskItem): String {
    val base = workStatusLabel(task.status)
    return if (task.qualityPercent != null) "$base · ${task.qualityPercent}%" else base
}

internal fun workStatusLabel(status: String): String {
    return when (status) {
        "awaiting_approval" -> "Chờ duyệt"
        "approval_returned" -> "Bị trả lại"
        "unreleased" -> "Chờ duyệt (chưa giao)"
        "unassigned" -> "Chưa giao việc"
        "in_progress" -> "Đang thực hiện"
        "not_completed" -> "Chưa hoàn thành"
        "pending_task", "pending" -> "Chưa hoàn thành"
        "overdue" -> "Quá hạn"
        "pending_completion", "pending_approval" -> "Chờ duyệt hoàn thành"
        "completed", "approved", "done" -> "Đã hoàn thành"
        "completed_late" -> "Hoàn thành muộn"
        "rejected_completion", "rejected" -> "Bị từ chối"
        else -> status
    }
}

internal fun workStatusTone(status: String): StatusTone = when (status) {
    "completed", "approved", "done" -> StatusTone.Positive
    "overdue", "rejected_completion", "rejected", "approval_returned" -> StatusTone.Warning
    "pending_completion", "pending_approval", "awaiting_approval", "unreleased" -> StatusTone.Primary
    else -> StatusTone.Neutral
}

package lvt.crm.ui.work

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean
import lvt.crm.data.convex.ConvexException
import lvt.crm.data.convex.ConvexHttpClient
import lvt.crm.data.work.WorkRepository
import lvt.crm.data.work.WorkOperations
import lvt.crm.data.work.WorkApprovalItem
import lvt.crm.data.work.WorkApprovalPolicy
import lvt.crm.data.work.WorkCompletionReviewItem
import lvt.crm.data.work.WorkTaskItem
import lvt.crm.data.work.WorkCreateAssignment
import lvt.crm.data.work.WorkCreatePolicy
import lvt.crm.data.work.WorkDocumentActions
import lvt.crm.data.work.WorkDocumentType
import lvt.crm.data.work.WorkFormOptions
import lvt.crm.ui.components.ListSearchState

data class WorkUiState(
    val loading: Boolean = true,
    val refreshing: Boolean = false,
    val error: String? = null,
    val actionError: String? = null,
    val isAdmin: Boolean = false,
    val accessLevel: Int = 0,
    val tasks: List<WorkTaskItem> = emptyList(),
    val approvals: List<WorkApprovalItem> = emptyList(),
    val busyTaskId: String? = null,
    val busyApprovalId: String? = null,
    val busyReviewId: String? = null,
    val qualityPromptTask: WorkTaskItem? = null,
    val qualityInput: String = "100",
    val evidencePromptTask: WorkTaskItem? = null,
    val evidenceNote: String = "",
    val completionReviews: List<WorkCompletionReviewItem> = emptyList(),
    val canCreate: Boolean = false,
    val isOps: Boolean = false,
    val formOptions: WorkFormOptions? = null,
    val formOptionsLoading: Boolean = false,
    val creating: Boolean = false,
    val notice: String? = null,
    val documentTypes: List<WorkDocumentType> = emptyList(),
    val mineTab: WorkListTab = WorkListTab.Todo,
    val createdTab: WorkListTab = WorkListTab.Todo,
    val needsExecutionOnly: Boolean = false,
    val search: ListSearchState = ListSearchState(),
    /** Ban giám hiệu "Chờ tôi duyệt" queue (awaiting first, then 30-day history). */
    val approvalQueue: List<WorkApprovalItem> = emptyList(),
    val currentUserId: String = "",
) {
    val awaitingApprovals: List<WorkApprovalItem>
        get() = approvalQueue.filter { it.awaitingMyDecision }
    val decidedApprovals: List<WorkApprovalItem>
        get() = approvalQueue.filterNot { it.awaitingMyDecision }
    val tabMine: List<WorkTaskItem>
        get() = filterTasksByTab(tasks, mineTab)
    val tabCreated: List<WorkApprovalItem>
        get() = filterDocumentsByTab(approvals, createdTab)
    val visibleMine: List<WorkTaskItem>
        get() = filterTasksBySearch(tabMine, search)
    val visibleCreated: List<WorkApprovalItem>
        get() = filterDocumentsBySearch(tabCreated, search)
    val mineSearchEmpty: Boolean
        get() = tabMine.isNotEmpty() && visibleMine.isEmpty()
    val createdSearchEmpty: Boolean
        get() = tabCreated.isNotEmpty() && visibleCreated.isEmpty()
    val mineTabCounts: Map<WorkListTab, Int>
        get() = countTasksByTab(tasks)
    val createdTabCounts: Map<WorkListTab, Int>
        get() = countDocumentsByTab(approvals)
}

class WorkViewModel(
    private val repository: WorkOperations,
) : ViewModel() {
    private val operationMutex = Mutex()
    private val refreshPending = AtomicBoolean(false)
    private val localCompletions = mutableMapOf<String, LocalTaskCompletion>()
    private val _uiState = MutableStateFlow(WorkUiState())
    val uiState: StateFlow<WorkUiState> = _uiState.asStateFlow()

    init {
        refresh(initial = true)
    }

    fun loadFormOptions() {
        _uiState.update { it.copy(formOptionsLoading = true, actionError = null) }
        viewModelScope.launch {
            try {
                val options = repository.formOptions()
                _uiState.update {
                    it.copy(
                        formOptions = options,
                        formOptionsLoading = false,
                        isOps = options.isOps,
                        documentTypes = options.documentTypes.ifEmpty { it.documentTypes },
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        formOptionsLoading = false,
                        actionError = (e as? ConvexException)?.message
                            ?: ConvexHttpClient.humanize(e.message ?: "LOAD_FAILED"),
                    )
                }
            }
        }
    }

    fun createDocument(
        title: String,
        assignments: List<WorkCreateAssignment>,
        fileBytes: ByteArray? = null,
        fileName: String? = null,
        mimeType: String? = null,
        documentTypeId: String = "",
        approverIds: List<String> = emptyList(),
        onSuccess: () -> Unit,
    ) {
        val hasFile = fileBytes != null && fileName != null && mimeType != null
        val requiresApproval = _uiState.value.formOptions?.requiresApproval == true
        val needsApproval = WorkApprovalPolicy.approverRequired(requiresApproval, assignments, _uiState.value.currentUserId)
        val validationError = WorkCreatePolicy.validate(title, assignments, hasFile, documentTypeId)
            ?: WorkApprovalPolicy.validateApprovers(requiresApproval, assignments, _uiState.value.currentUserId, approverIds)
        if (validationError != null) {
            _uiState.update { it.copy(actionError = validationError) }
            return
        }
        _uiState.update { it.copy(creating = true, actionError = null) }
        viewModelScope.launch {
            operationMutex.withLock {
                try {
                    val evidence = if (hasFile) {
                        repository.uploadEvidence(fileBytes!!, fileName!!, mimeType!!)
                    } else {
                        null
                    }
                    repository.createDocument(
                        title,
                        assignments,
                        evidence,
                        documentTypeId.takeIf { it.isNotBlank() },
                        approverIds.takeIf { requiresApproval && it.isNotEmpty() },
                    )
                    reloadAfterCommittedMutation()
                    _uiState.update {
                        it.copy(notice = WorkApprovalPolicy.savedNotice(editing = false, needsApproval = needsApproval))
                    }
                    onSuccess()
                } catch (e: Exception) {
                    _uiState.update {
                        it.copy(actionError = documentActionError(e, deleting = false, fallbackCode = "CREATE_FAILED"))
                    }
                } finally {
                    _uiState.update { it.copy(creating = false) }
                }
            }
            runPendingRefresh()
        }
    }

    fun updateDocument(
        documentId: String,
        title: String,
        assignments: List<WorkCreateAssignment>,
        fileBytes: ByteArray? = null,
        fileName: String? = null,
        mimeType: String? = null,
        documentTypeId: String = "",
        requiresApproval: Boolean = false,
        approverIds: List<String> = emptyList(),
        onSuccess: () -> Unit,
    ) {
        val needsApproval = WorkApprovalPolicy.approverRequired(requiresApproval, assignments, _uiState.value.currentUserId)
        val approverError = WorkApprovalPolicy.validateApprovers(
            requiresApproval,
            assignments,
            _uiState.value.currentUserId,
            approverIds,
        )
        saveDocument(
            deleting = false,
            title = title,
            assignments = assignments,
            fileBytes = fileBytes,
            fileName = fileName,
            mimeType = mimeType,
            documentTypeId = documentTypeId,
            extraValidationError = approverError,
            onSuccess = onSuccess,
        ) { evidence ->
            repository.updateDocument(
                documentId,
                title,
                assignments,
                evidence,
                documentTypeId.takeIf { it.isNotBlank() },
                approverIds.takeIf { requiresApproval && it.isNotEmpty() },
            )
            WorkApprovalPolicy.savedNotice(editing = true, needsApproval = needsApproval)
        }
    }

    fun deleteDocument(documentId: String, onSuccess: () -> Unit = {}) {
        _uiState.update { it.copy(creating = true, actionError = null) }
        viewModelScope.launch {
            operationMutex.withLock {
                try {
                    repository.deleteDocument(documentId)
                    reloadAfterCommittedMutation()
                    _uiState.update { it.copy(notice = "Đã xóa công việc.") }
                    onSuccess()
                } catch (e: Exception) {
                    _uiState.update {
                        it.copy(actionError = documentActionError(e, deleting = true))
                    }
                } finally {
                    _uiState.update { it.copy(creating = false) }
                }
            }
            runPendingRefresh()
        }
    }

    private fun saveDocument(
        deleting: Boolean,
        title: String,
        assignments: List<WorkCreateAssignment>,
        fileBytes: ByteArray?,
        fileName: String?,
        mimeType: String?,
        documentTypeId: String,
        extraValidationError: String? = null,
        onSuccess: () -> Unit,
        persist: suspend (lvt.crm.data.work.WorkUploadedEvidence?) -> String,
    ) {
        val hasFile = fileBytes != null && fileName != null && mimeType != null
        val validationError = WorkCreatePolicy.validate(title, assignments, hasFile, documentTypeId)
            ?: extraValidationError
        if (validationError != null) {
            _uiState.update { it.copy(actionError = validationError) }
            return
        }
        _uiState.update { it.copy(creating = true, actionError = null) }
        viewModelScope.launch {
            operationMutex.withLock {
                try {
                    val evidence = if (hasFile) {
                        repository.uploadEvidence(fileBytes!!, fileName!!, mimeType!!)
                    } else {
                        null
                    }
                    val savedNotice = persist(evidence)
                    reloadAfterCommittedMutation()
                    _uiState.update { it.copy(notice = savedNotice) }
                    onSuccess()
                } catch (e: Exception) {
                    _uiState.update {
                        it.copy(actionError = documentActionError(e, deleting = deleting))
                    }
                } finally {
                    _uiState.update { it.copy(creating = false) }
                }
            }
            runPendingRefresh()
        }
    }

    private fun documentActionError(error: Exception, deleting: Boolean, fallbackCode: String? = null): String {
        val raw = when (error) {
            is ConvexException -> "${error.code} ${error.message.orEmpty()}"
            else -> error.message.orEmpty()
        }
        val fallback = (error as? ConvexException)?.message
            ?: ConvexHttpClient.humanize(
                error.message ?: fallbackCode ?: if (deleting) "DELETE_FAILED" else "UPDATE_FAILED",
            )
        return WorkDocumentActions.errorMessage(raw, deleting, fallback)
    }

    fun refresh(initial: Boolean = false) {
        if (!operationMutex.tryLock()) {
            refreshPending.set(true)
            return
        }
        _uiState.update {
            it.copy(loading = initial, refreshing = !initial, error = null, actionError = null)
        }
        viewModelScope.launch {
            try {
                val snap = repository.listMine()
                dropResolvedLocalCompletions(snap.tasks)
                _uiState.update {
                    it.copy(
                        loading = false,
                        refreshing = false,
                        isAdmin = snap.isAdmin,
                        accessLevel = snap.accessLevel,
                        canCreate = snap.canCreate,
                        isOps = snap.isOps,
                        tasks = overlayLocalCompletions(snap.tasks),
                        approvals = snap.approvals,
                        completionReviews = snap.completionReviews,
                        documentTypes = snap.documentTypes,
                        approvalQueue = WorkApprovalPolicy.orderedQueue(snap.approvalQueue),
                        currentUserId = snap.currentUserId,
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        loading = false,
                        refreshing = false,
                        error = (e as? ConvexException)?.message
                            ?: ConvexHttpClient.humanize(e.message ?: "LOAD_FAILED"),
                    )
                }
            } finally {
                releaseOperation()
            }
        }
    }

    fun setMineTab(tab: WorkListTab) {
        _uiState.update { it.copy(mineTab = tab, needsExecutionOnly = false) }
    }

    fun setCreatedTab(tab: WorkListTab) {
        _uiState.update { it.copy(createdTab = tab) }
    }

    fun updateSearch(search: ListSearchState) {
        _uiState.update { it.copy(search = search) }
    }

    fun applyDashboardFilter(filter: WorkDashboardFilter) {
        _uiState.update { state ->
            when (filter) {
                WorkDashboardFilter.PendingApproval -> state.copy(
                    mineTab = WorkListTab.PendingReview,
                    createdTab = WorkListTab.PendingReview,
                    needsExecutionOnly = false,
                )
                WorkDashboardFilter.NeedsExecution -> state.copy(
                    mineTab = WorkListTab.Todo,
                    needsExecutionOnly = false,
                )
            }
        }
    }

    fun requestComplete(task: WorkTaskItem) {
        if (task.isAdmin) {
            _uiState.update {
                it.copy(qualityPromptTask = task, qualityInput = "100", actionError = null)
            }
        } else {
            _uiState.update {
                it.copy(evidencePromptTask = task, evidenceNote = "", actionError = null)
            }
        }
    }

    fun dismissEvidencePrompt() {
        _uiState.update { it.copy(evidencePromptTask = null, evidenceNote = "") }
    }

    fun onEvidenceNoteChange(value: String) {
        _uiState.update { it.copy(evidenceNote = value.take(500)) }
    }

    fun setActionError(error: String) {
        _uiState.update { it.copy(actionError = error) }
    }

    fun completeWithEvidence(
        task: WorkTaskItem,
        fileBytes: ByteArray,
        fileName: String,
        mimeType: String,
        documentTypeId: String = "",
    ) {
        if (task.kind == WorkTaskItem.Kind.WorkItem && documentTypeId.isBlank()) {
            _uiState.update { it.copy(actionError = "Vui lòng chọn loại văn bản.") }
            return
        }
        complete(
            task,
            qualityPercent = null,
            fileBytes = fileBytes,
            fileName = fileName,
            mimeType = mimeType,
            documentTypeId = documentTypeId,
        )
    }

    /**
     * Ban giám hiệu decision: approve (irreversible; the first approval locks edit/delete) or
     * return with a required reason. Returns false when the reason is invalid (nothing is sent).
     */
    fun decideApproval(approval: WorkApprovalItem, approve: Boolean, reason: String? = null): Boolean {
        if (!approve) {
            WorkApprovalPolicy.validateReturnReason(reason.orEmpty())?.let { message ->
                _uiState.update { it.copy(actionError = message) }
                return false
            }
        }
        _uiState.update { it.copy(busyApprovalId = approval.id, actionError = null, notice = null) }
        viewModelScope.launch {
            operationMutex.withLock {
                try {
                    repository.decideApproval(approval.id, approve, reason?.trim())
                    _uiState.update { state ->
                        state.copy(
                            approvalQueue = state.approvalQueue.map { item ->
                                if (item.id == approval.id) {
                                    item.copy(
                                        myDecision = if (approve) "approved" else "rejected",
                                        awaitingMyDecision = false,
                                        canReject = false,
                                    )
                                } else {
                                    item
                                }
                            },
                            notice = if (approve) "Bạn đã duyệt công việc." else "Đã trả lại công việc cho người tạo.",
                        )
                    }
                    reloadAfterCommittedMutation()
                } catch (e: Exception) {
                    _uiState.update {
                        it.copy(
                            actionError = (e as? ConvexException)?.message
                                ?: ConvexHttpClient.humanize(e.message ?: "APPROVAL_FAILED"),
                        )
                    }
                } finally {
                    if (_uiState.value.busyApprovalId == approval.id) {
                        _uiState.update { it.copy(busyApprovalId = null) }
                    }
                }
            }
            runPendingRefresh()
        }
        return true
    }

    fun onQualityInput(value: String) {
        _uiState.update { it.copy(qualityInput = value.filter { ch -> ch.isDigit() }.take(3)) }
    }

    fun reviewCompletion(
        review: WorkCompletionReviewItem,
        approve: Boolean,
        qualityPercent: Int? = null,
        rejectionReason: String? = null,
    ) {
        val operationId = review.workItemId + review.userId
        _uiState.update { it.copy(busyReviewId = operationId, actionError = null) }
        viewModelScope.launch {
            operationMutex.withLock {
                try {
                    repository.reviewCompletion(review, approve, qualityPercent, rejectionReason)
                    _uiState.update { state ->
                        state.copy(
                            completionReviews = state.completionReviews.filterNot {
                                it.workItemId == review.workItemId && it.userId == review.userId
                            },
                        )
                    }
                    reloadAfterCommittedMutation()
                } catch (e: Exception) {
                    _uiState.update {
                        it.copy(
                            actionError = (e as? ConvexException)?.message
                                ?: ConvexHttpClient.humanize(e.message ?: "COMPLETION_REVIEW_FAILED"),
                        )
                    }
                } finally {
                    if (_uiState.value.busyReviewId == operationId) {
                        _uiState.update { it.copy(busyReviewId = null) }
                    }
                }
            }
            runPendingRefresh()
        }
    }

    fun dismissQualityPrompt() {
        _uiState.update { it.copy(qualityPromptTask = null) }
    }

    fun confirmQualityComplete() {
        val task = _uiState.value.qualityPromptTask ?: return
        val pct = _uiState.value.qualityInput.toIntOrNull()
        if (pct == null || pct < 0 || pct > 100) {
            _uiState.update { it.copy(actionError = "Nhập % chất lượng từ 0 đến 100.") }
            return
        }
        complete(task, qualityPercent = pct)
        _uiState.update { it.copy(qualityPromptTask = null) }
    }

    private fun complete(
        task: WorkTaskItem,
        qualityPercent: Int?,
        fileBytes: ByteArray? = null,
        fileName: String? = null,
        mimeType: String? = null,
        documentTypeId: String = "",
    ) {
        val note = _uiState.value.evidenceNote.trim().ifBlank { null }
        _uiState.update { it.copy(busyTaskId = task.id, actionError = null, evidencePromptTask = null, evidenceNote = "") }
        viewModelScope.launch {
            operationMutex.withLock {
                try {
                    val evidence = if (fileBytes != null && fileName != null && mimeType != null) {
                        repository.uploadEvidence(fileBytes, fileName, mimeType)
                    } else null
                    repository.complete(
                        task,
                        qualityPercent,
                        evidence,
                        note,
                        documentTypeId.takeIf { it.isNotBlank() },
                    )
                    rememberLocalCompletion(task, qualityPercent)
                    _uiState.update { state ->
                        state.copy(tasks = overlayLocalCompletions(state.tasks))
                    }
                    reloadAfterCommittedMutation()
                } catch (e: Exception) {
                    _uiState.update {
                        it.copy(
                            actionError = (e as? ConvexException)?.message
                                ?: ConvexHttpClient.humanize(e.message ?: "COMPLETE_FAILED"),
                        )
                    }
                } finally {
                    if (_uiState.value.busyTaskId == task.id) {
                        _uiState.update { it.copy(busyTaskId = null) }
                    }
                }
            }
            runPendingRefresh()
        }
    }

    private suspend fun reloadAfterCommittedMutation() {
        try {
            val snap = repository.listMine()
            dropResolvedLocalCompletions(snap.tasks)
            _uiState.update {
                it.copy(
                    isAdmin = snap.isAdmin,
                    accessLevel = snap.accessLevel,
                    canCreate = snap.canCreate,
                    isOps = snap.isOps,
                    tasks = overlayLocalCompletions(snap.tasks),
                    approvals = snap.approvals,
                    completionReviews = snap.completionReviews,
                    documentTypes = snap.documentTypes,
                    approvalQueue = WorkApprovalPolicy.orderedQueue(snap.approvalQueue),
                    currentUserId = snap.currentUserId,
                )
            }
        } catch (_: Exception) {
            _uiState.update {
                it.copy(actionError = "Thao tác đã được lưu, nhưng chưa tải lại được danh sách. Hãy làm mới.")
            }
        }
    }

    private fun releaseOperation() {
        operationMutex.unlock()
        runPendingRefresh()
    }

    private fun runPendingRefresh() {
        if (refreshPending.getAndSet(false)) refresh()
    }

    private fun rememberLocalCompletion(task: WorkTaskItem, qualityPercent: Int?) {
        localCompletions[localCompletionKey(task.kind, task.id)] = LocalTaskCompletion(
            status = if (qualityPercent != null) "completed" else "pending_completion",
            qualityPercent = qualityPercent,
        )
    }

    private fun dropResolvedLocalCompletions(tasks: List<WorkTaskItem>) {
        if (localCompletions.isEmpty()) return
        for (item in tasks) {
            if (serverHasCompletion(item)) {
                localCompletions.remove(localCompletionKey(item.kind, item.id))
            }
        }
    }

    private fun overlayLocalCompletions(tasks: List<WorkTaskItem>): List<WorkTaskItem> {
        if (localCompletions.isEmpty()) return tasks
        return tasks.map { item ->
            val local = localCompletions[localCompletionKey(item.kind, item.id)] ?: return@map item
            if (serverHasCompletion(item)) {
                item
            } else {
                item.copy(
                    status = local.status,
                    qualityPercent = local.qualityPercent ?: item.qualityPercent,
                )
            }
        }
    }

    private fun serverHasCompletion(item: WorkTaskItem): Boolean =
        isTaskPendingReview(item) || isTaskCompleted(item)

    private data class LocalTaskCompletion(
        val status: String,
        val qualityPercent: Int?,
    )

    private fun localCompletionKey(kind: WorkTaskItem.Kind, id: String) = "$kind-$id"

    companion object {
        fun factory(repository: WorkRepository): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return WorkViewModel(repository) as T
                }
            }
    }
}

package lvt.crm.ui.work

import java.util.Calendar
import java.util.TimeZone
import lvt.crm.data.work.WorkApprovalItem
import lvt.crm.data.work.WorkTaskItem
import lvt.crm.data.work.needsCompletion
import lvt.crm.ui.components.ListSearchState
import lvt.crm.ui.components.anyDateInRange
import lvt.crm.ui.components.includesListSearch
import lvt.crm.ui.components.normalizeListSearchText

enum class WorkDashboardFilter {
    PendingApproval,
    NeedsExecution,
}

enum class WorkListTab {
    Todo,
    PendingReview,
    Overdue,
    Completed,
    ;

    val title: String
        get() = when (this) {
            Todo -> "Việc cần làm"
            PendingReview -> "Đang chờ duyệt"
            Overdue -> "Quá hạn"
            Completed -> "Đã duyệt hoàn thành"
        }
}

private val completedStatuses = setOf("completed", "completed_late")
private val pendingReviewStatuses = setOf("pending_completion", "pending_approval")

/** `awaiting_approval` = document waiting for Ban giám hiệu (web workDisplay.js PENDING_REVIEW_STATUSES). */
private val documentPendingReviewStatuses = pendingReviewStatuses + "awaiting_approval"

/** Server list status wins over the document approval status (web: `workStatus || status`). */
private fun WorkApprovalItem.listStatus(): String = workStatus.ifBlank { status }

fun vietnamToday(nowMillis: Long = System.currentTimeMillis()): String {
    val calendar = Calendar.getInstance(TimeZone.getTimeZone("GMT+07:00"))
    calendar.timeInMillis = nowMillis
    val year = calendar.get(Calendar.YEAR)
    val month = calendar.get(Calendar.MONTH) + 1
    val day = calendar.get(Calendar.DAY_OF_MONTH)
    return "%04d-%02d-%02d".format(year, month, day)
}

fun isTaskCompleted(task: WorkTaskItem): Boolean = task.status in completedStatuses

fun isTaskPendingReview(task: WorkTaskItem): Boolean = task.status in pendingReviewStatuses

fun isDocumentCompleted(document: WorkApprovalItem): Boolean {
    if (document.listStatus() in completedStatuses) return true
    val assignmentStatuses = document.assignments.map { it.status }
    return assignmentStatuses.isNotEmpty() && assignmentStatuses.all { it in completedStatuses }
}

fun isDocumentPendingReview(document: WorkApprovalItem): Boolean {
    if (document.listStatus() in documentPendingReviewStatuses) return true
    return document.assignments.any { it.status in pendingReviewStatuses }
}

fun isTaskOverdue(task: WorkTaskItem, today: String = vietnamToday()): Boolean {
    if (isTaskCompleted(task)) return false
    if (task.deadline.isBlank()) return false
    return task.deadline < today
}

fun isDocumentOverdue(document: WorkApprovalItem, today: String = vietnamToday()): Boolean {
    if (isDocumentCompleted(document)) return false
    val deadlines = document.assignments.map { it.deadline }.filter { it.isNotBlank() }
        .ifEmpty { listOfNotNull(document.deadline.takeIf { it.isNotBlank() }) }
    if (deadlines.isEmpty()) return false
    return deadlines.all { it < today }
}

fun isTaskPast(task: WorkTaskItem, today: String = vietnamToday()): Boolean {
    if (isTaskCompleted(task)) return true
    return isTaskOverdue(task, today)
}

fun isDocumentPast(document: WorkApprovalItem, today: String = vietnamToday()): Boolean {
    if (isDocumentCompleted(document)) return true
    return isDocumentOverdue(document, today)
}

fun filterTasksByTab(list: List<WorkTaskItem>, tab: WorkListTab, today: String = vietnamToday()): List<WorkTaskItem> {
    return list.filter { tabForTask(it, today) == tab }.sortedBy { it.deadline }
}

fun filterDocumentsByTab(
    list: List<WorkApprovalItem>,
    tab: WorkListTab,
    today: String = vietnamToday(),
): List<WorkApprovalItem> {
    return list.filter { tabForDocument(it, today) == tab }.sortedBy { document ->
        document.assignments.map { it.deadline }.filter { it.isNotBlank() }.minOrNull()
            ?: document.deadline
    }
}

fun countTasksByTab(list: List<WorkTaskItem>, today: String = vietnamToday()): Map<WorkListTab, Int> {
    val counts = WorkListTab.entries.associateWith { 0 }.toMutableMap()
    for (task in list) {
        val tab = tabForTask(task, today)
        counts[tab] = counts.getValue(tab) + 1
    }
    return counts
}

fun countDocumentsByTab(list: List<WorkApprovalItem>, today: String = vietnamToday()): Map<WorkListTab, Int> {
    val counts = WorkListTab.entries.associateWith { 0 }.toMutableMap()
    for (document in list) {
        val tab = tabForDocument(document, today)
        counts[tab] = counts.getValue(tab) + 1
    }
    return counts
}

fun filterTasksNeedingExecution(list: List<WorkTaskItem>): List<WorkTaskItem> =
    list.filter { needsCompletion(it.status) }.sortedBy { it.deadline }

fun tabForTask(task: WorkTaskItem, today: String = vietnamToday()): WorkListTab =
    when {
        isTaskCompleted(task) -> WorkListTab.Completed
        isTaskPendingReview(task) -> WorkListTab.PendingReview
        isTaskOverdue(task, today) -> WorkListTab.Overdue
        else -> WorkListTab.Todo
    }

fun tabForDocument(document: WorkApprovalItem, today: String = vietnamToday()): WorkListTab =
    when {
        isDocumentCompleted(document) -> WorkListTab.Completed
        isDocumentPendingReview(document) -> WorkListTab.PendingReview
        isDocumentOverdue(document, today) -> WorkListTab.Overdue
        else -> WorkListTab.Todo
    }

fun filterTasksBySearch(list: List<WorkTaskItem>, search: ListSearchState): List<WorkTaskItem> {
    val query = normalizeListSearchText(search.query)
    val department = normalizeListSearchText(search.department)
    val person = normalizeListSearchText(search.person)
    val dateFrom = search.dateFrom.trim()
    val dateTo = search.dateTo.trim()
    if (query.isBlank() && department.isBlank() && person.isBlank() && dateFrom.isBlank() && dateTo.isBlank()) {
        return list
    }
    return list.filter { task ->
        val queryText = listOf(task.title, task.documentTitle, task.fileName, task.documentContent)
            .joinToString(" ")
        if (query.isNotBlank() && !includesListSearch(queryText, query)) return@filter false
        if (!includesListSearch(task.departmentName, department)) return@filter false
        if (!includesListSearch(task.memberNames.joinToString(" "), person)) return@filter false
        anyDateInRange(listOf(task.deadline), dateFrom, dateTo)
    }
}

fun workListTitle(document: WorkApprovalItem): String {
    document.title.trim().takeIf { it.isNotEmpty() }?.let { return it }
    document.fileName.trim().takeIf { it.isNotEmpty() }?.let { return it }
    return document.content.trim().ifBlank { "Công việc" }
}

fun workListSubtitle(document: WorkApprovalItem): String? {
    val title = workListTitle(document)
    val content = document.content.trim()
    return content.takeIf { it.isNotEmpty() && it != title }
}

fun WorkTaskItem.hasAttachedFile(): Boolean = documentId.isNotBlank() && privateFile

fun WorkTaskItem.toAttachedDocument(): WorkApprovalItem = WorkApprovalItem(
    id = documentId,
    fileName = fileName,
    content = documentContent,
    deadline = deadline,
    status = status,
    approvalCount = 0,
    approvalTotal = 0,
    myDecision = "",
    fileUrl = fileUrl,
    privateFile = privateFile,
    title = documentTitle.ifBlank { title },
)

fun filterDocumentsBySearch(list: List<WorkApprovalItem>, search: ListSearchState): List<WorkApprovalItem> {
    val query = normalizeListSearchText(search.query)
    val department = normalizeListSearchText(search.department)
    val person = normalizeListSearchText(search.person)
    val dateFrom = search.dateFrom.trim()
    val dateTo = search.dateTo.trim()
    if (query.isBlank() && department.isBlank() && person.isBlank() && dateFrom.isBlank() && dateTo.isBlank()) {
        return list
    }
    return list.filter { document ->
        val queryText = buildList {
            add(document.title)
            add(document.fileName)
            add(document.content)
            document.assignments.forEach { add(it.content) }
        }.joinToString(" ")
        val departmentText = document.assignments.joinToString(" ") { it.departmentName }
        val personText = document.assignments
            .flatMap { assignment -> assignment.members.map { it.name } }
            .joinToString(" ")
        val deadlines = document.assignments.map { it.deadline }.filter { it.isNotBlank() }
            .ifEmpty { listOfNotNull(document.deadline.takeIf { it.isNotBlank() }) }
        if (query.isNotBlank() && !includesListSearch(queryText, query)) return@filter false
        if (!includesListSearch(departmentText, department)) return@filter false
        if (!includesListSearch(personText, person)) return@filter false
        anyDateInRange(deadlines, dateFrom, dateTo)
    }
}

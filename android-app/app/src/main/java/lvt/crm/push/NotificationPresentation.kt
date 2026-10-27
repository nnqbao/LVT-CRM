package lvt.crm.push

import lvt.crm.ui.duties.SharedWeekPresentation

/**
 * Labels for bell items and system notifications (pure, unit-tested).
 * Work approval kinds (backend `convex/notifications.ts`):
 * - `approval`: Ban giám hiệu "Công việc chờ duyệt" (dueAt = deadline);
 * - `work_approved` / `work_returned`: the creator's outcome (dueAt = decision time).
 * All three are kind `work` and open the Công việc screen focused on the document.
 * Kind `people` (Ghi nhận lỗi / Đánh giá nhân sự) opens that web page (no app screen):
 * `staff_fault`, `evaluation_text_review`, `evaluation_text_approved`, `evaluation_text_returned`.
 */
object NotificationPresentation {
    const val APPROVAL = "approval"
    const val WORK_APPROVED = "work_approved"
    const val WORK_RETURNED = "work_returned"
    const val STAFF_FAULT = "staff_fault"
    const val EVALUATION_RETURNED = "evaluation_text_returned"

    private val headlineMarkers = listOf(
        "Công việc chờ duyệt:",
        "Công việc bị trả lại:",
        "Công việc đã được duyệt:",
        "Công văn cần duyệt:",
    )

    fun isChat(sourceType: String) = NotificationDestination.opensChat(sourceType)

    /** Mirrors web peopleNotificationLabel (src/notifications/useNotificationFocus.js). */
    fun peopleLabel(sourceType: String) = if (sourceType == STAFF_FAULT) "Ghi nhận lỗi" else "Đánh giá nhân sự"

    fun kindLabel(kind: String, sourceType: String): String = when {
        kind == "people" -> peopleLabel(sourceType)
        isChat(sourceType) -> "Trao đổi"
        SharedWeekPresentation.isWeekNotification(sourceType) -> "Lịch công tác chung"
        kind == "duty" -> "Công tác"
        NotificationDestination.isTodo(kind, sourceType) -> "Việc của tôi"
        sourceType == "completion_rejected" -> "Từ chối hoàn thành"
        sourceType == APPROVAL -> "Công việc chờ duyệt"
        sourceType == WORK_APPROVED -> "Công việc đã duyệt"
        sourceType == WORK_RETURNED -> "Công việc bị trả lại"
        else -> "Công việc"
    }

    /** Red accent (web REJECTION_SOURCE_TYPES): a completion rejected, a work document or comment returned. */
    fun isRejection(sourceType: String) =
        sourceType == "completion_rejected" || sourceType == WORK_RETURNED || sourceType == EVALUATION_RETURNED

    /** "Lúc" (event time) instead of "Hạn" (deadline). */
    fun showsEventTime(sourceType: String) =
        isChat(sourceType) ||
            SharedWeekPresentation.isWeekNotification(sourceType) ||
            sourceType == WORK_APPROVED ||
            sourceType == WORK_RETURNED ||
            sourceType == STAFF_FAULT ||
            sourceType.startsWith("evaluation_text_")

    /** Splits "Công việc chờ duyệt: Kế hoạch" into the marker and the work title. */
    fun headline(title: String, kind: String, sourceType: String): Pair<String, String?> {
        val value = title.ifBlank { kindLabel(kind, sourceType) }
        val marker = headlineMarkers.firstOrNull { value.startsWith(it) } ?: return value to null
        return marker to value.removePrefix(marker).trim().takeIf { it.isNotBlank() }
    }

    fun systemTitle(kind: String, sourceType: String, milestoneLabel: String): String = when {
        kind == "people" -> if (sourceType == STAFF_FAULT) "Ghi nhận lỗi" else "Đánh giá nhân sự · ${milestoneLabel.ifBlank { "Nhận xét" }}"
        sourceType == "completion_rejected" -> "Hoàn thành bị từ chối"
        sourceType == WORK_RETURNED -> "Công việc bị trả lại"
        sourceType == WORK_APPROVED -> "Công việc đã được duyệt"
        sourceType == APPROVAL -> "Công việc chờ duyệt"
        isChat(sourceType) -> "Trao đổi · ${milestoneLabel.ifBlank { "Tin nhắn mới" }}"
        kind == "duty" -> "Công tác · $milestoneLabel"
        NotificationDestination.isTodo(kind, sourceType) -> "Việc của tôi · ${milestoneLabel.ifBlank { "Nhắc việc" }}"
        else -> "Công việc · $milestoneLabel"
    }
}

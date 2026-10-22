package lvt.crm.data.work

data class WorkFormDepartment(
    val id: String,
    val name: String,
)

data class WorkFormUser(
    val id: String,
    val name: String,
    val departmentName: String,
    val level: Int,
    val positionName: String = "",
)

data class WorkDocumentType(
    val id: String,
    val name: String,
    val code: String = "",
)

data class WorkFormOptions(
    val canCreate: Boolean,
    val isOps: Boolean,
    val departments: List<WorkFormDepartment>,
    val users: List<WorkFormUser>,
    val documentTypes: List<WorkDocumentType> = emptyList(),
    /** Server flag: documents this creator makes go to Ban giám hiệu before release (admin/mod). */
    val requiresApproval: Boolean = false,
    /** Server flag: may assign whole departments (admin/mod and Ban giám hiệu). */
    val canAssignDepartments: Boolean = isOps,
    /** Eligible Ban giám hiệu approvers (only filled for approval-required creators). */
    val approvers: List<WorkFormUser> = emptyList(),
)

data class WorkCreateAssignment(
    val type: String,
    val departmentId: String = "",
    val userIds: List<String> = emptyList(),
    val content: String = "",
    val deadline: String = "",
) {
    val isIndividual: Boolean get() = type == "individual"
}

fun formatWorkDeadline(millis: Long): String {
    val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("GMT+7"))
    cal.timeInMillis = millis
    return String.format(
        "%04d-%02d-%02d",
        cal.get(java.util.Calendar.YEAR),
        cal.get(java.util.Calendar.MONTH) + 1,
        cal.get(java.util.Calendar.DAY_OF_MONTH),
    )
}

object WorkCreatePolicy {
    fun validate(
        title: String,
        assignments: List<WorkCreateAssignment>,
        hasFile: Boolean = false,
        documentTypeId: String = "",
    ): String? {
        if (title.trim().isEmpty() || title.trim().length > 200) {
            return "Vui lòng nhập tên công việc (tối đa 200 ký tự)."
        }
        if (assignments.isEmpty()) {
            return "Vui lòng thêm ít nhất một phân công."
        }
        if (hasFile && documentTypeId.trim().isEmpty()) {
            return "Vui lòng chọn loại văn bản."
        }
        assignments.forEachIndexed { index, row ->
            val label = "Phân công ${index + 1}"
            if (row.isIndividual) {
                if (row.userIds.none { it.isNotBlank() }) return "$label: chọn người nhận."
            } else if (row.departmentId.isBlank()) {
                return "$label: chọn phòng ban."
            }
            if (row.content.trim().isEmpty() || row.content.trim().length > 2000) {
                return "$label: nhập nội dung công việc (tối đa 2000 ký tự)."
            }
            if (!DATE_RE.matches(row.deadline.trim())) {
                return "$label: chọn hạn chót."
            }
        }
        return null
    }

    private val DATE_RE = Regex("""^\d{4}-\d{2}-\d{2}$""")
}

const val WORK_LOCKED_MESSAGE = "Đã có người nộp · Không thể sửa hoặc xóa"
const val WORK_APPROVAL_LOCKED_MESSAGE = "Ban giám hiệu đã duyệt · Không thể sửa hoặc xóa"
const val WORK_IMMUTABLE_ERROR_MESSAGE =
    "Công việc đã có người duyệt hoặc người nộp nên không thể sửa hoặc xóa."

/**
 * Edit/delete visibility follows the server's `canEdit` / `canDelete` exactly (web parity).
 * The first Ban giám hiệu approval locks the document for everyone, admin/mod included,
 * so a locked document never shows the buttons even if a stale flag says otherwise.
 */
object WorkDocumentActions {
    fun showsEdit(document: WorkApprovalItem) = document.canEdit && !document.approvalLocked

    fun showsDelete(document: WorkApprovalItem) = document.canDelete && !document.approvalLocked

    fun lockedMessage(document: WorkApprovalItem): String? = when {
        showsEdit(document) || showsDelete(document) -> null
        document.approvalLocked -> WORK_APPROVAL_LOCKED_MESSAGE
        else -> WORK_LOCKED_MESSAGE
    }

    fun errorMessage(raw: String, deleting: Boolean, fallback: String): String {
        lvt.crm.data.convex.WorkErrorMessages.messageFor(raw)?.let { return it }
        if (deleting) return "Không thể xóa công việc lúc này."
        return fallback
    }
}

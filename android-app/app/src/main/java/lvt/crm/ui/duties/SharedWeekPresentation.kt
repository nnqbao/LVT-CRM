package lvt.crm.ui.duties

import lvt.crm.data.duties.DutyWeekState
import lvt.crm.data.duties.SharedDutyEvent
import lvt.crm.ui.homeroom.HomeroomTone
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Wording and grouping for the weekly Lịch công tác chung (same rules as the web sheet). */
object SharedWeekPresentation {
    private val vietnam: ZoneId = ZoneId.of("Asia/Ho_Chi_Minh")
    private val weekdays = listOf("Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ Nhật")

    data class Copy(val text: String, val hint: String?)
    data class Day(val iso: String, val title: String, val events: List<SharedDutyEvent>)

    fun weekStart(anchorIso: String): String {
        val date = LocalDate.parse(anchorIso)
        return date.minusDays((date.dayOfWeek.value - 1).toLong()).toString()
    }

    fun weekEnd(weekStart: String): String = LocalDate.parse(weekStart).plusDays(5).toString()

    fun shiftWeek(weekStart: String, direction: Int): String =
        LocalDate.parse(weekStart).plusWeeks(direction.toLong()).toString()

    private fun dayMonth(iso: String): String {
        val date = LocalDate.parse(iso)
        return "%02d/%02d".format(date.dayOfMonth, date.monthValue)
    }

    fun weekLabel(weekStart: String): String = "Tuần ${dayMonth(weekStart)} – ${dayMonth(weekEnd(weekStart))}"

    fun dayTitle(iso: String): String {
        val date = LocalDate.parse(iso)
        return "${weekdays[date.dayOfWeek.value - 1]} ${dayMonth(iso)}"
    }

    /** "14:00" → "14g00", the way the school writes it on paper. */
    fun clock(value: String): String {
        val match = Regex("^(\\d{1,2}):(\\d{2})").find(value.trim()) ?: return value.trim()
        return "${match.groupValues[1].toInt()}g${match.groupValues[2]}"
    }

    fun timeLabel(event: SharedDutyEvent): String = when {
        event.startDate != event.endDate -> "Đến ${dayMonth(event.endDate)}"
        event.allDay -> "Cả ngày"
        else -> clock(event.startTime)
    }

    fun participants(event: SharedDutyEvent): String {
        val parts = mutableListOf<String>()
        (event.departmentNames + event.participantNames + listOf(event.otherParticipants)).forEach { name ->
            val label = name.trim()
            if (label.isNotEmpty() && label !in parts) parts += label
        }
        return parts.joinToString(", ")
    }

    fun hasParticipants(event: SharedDutyEvent): Boolean =
        event.departmentIds.isNotEmpty() || event.participantUserIds.isNotEmpty() || event.otherParticipants.isNotBlank()

    /** Monday to Saturday; a duty that began last week shows on Monday. */
    fun days(weekStart: String, events: List<SharedDutyEvent>): List<Day> {
        val start = LocalDate.parse(weekStart)
        val isoDays = (0..5).map { start.plusDays(it.toLong()).toString() }
        val byDay = isoDays.associateWith { mutableListOf<SharedDutyEvent>() }
        events.forEach { event ->
            if (event.endDate < isoDays.first() || event.startDate > isoDays.last()) return@forEach
            val day = if (event.startDate < isoDays.first()) isoDays.first() else event.startDate
            byDay[day]?.add(event)
        }
        return isoDays.map { iso ->
            val sorted = byDay.getValue(iso).sortedWith(
                compareBy<SharedDutyEvent>({ if (it.allDay || it.startDate != it.endDate) "0" else "1-${it.startTime}" }, { it.title }),
            )
            Day(iso, dayTitle(iso), sorted)
        }
    }

    fun pill(status: String): String = when (status) {
        "draft" -> "Nháp"
        "submitted" -> "Chờ duyệt"
        "returned" -> "Bị trả lại"
        "approved" -> "Đã duyệt"
        "approved_changed" -> "Đã duyệt · có thay đổi chờ duyệt"
        else -> "Chưa có lịch"
    }

    fun tone(status: String): HomeroomTone = when (status) {
        "submitted", "approved_changed" -> HomeroomTone.Warning
        "returned" -> HomeroomTone.Danger
        "approved" -> HomeroomTone.Success
        else -> HomeroomTone.Neutral
    }

    fun changeLabel(kind: String): String = when (kind) {
        "added" -> "Thêm"
        "removed" -> "Xóa"
        "moved_out" -> "Chuyển tuần"
        else -> "Sửa"
    }

    /** "lúc 10:20, 17/10" in Vietnam time. */
    fun moment(ms: Double?): String {
        if (ms == null || ms <= 0) return ""
        val time = Instant.ofEpochMilli(ms.toLong()).atZone(vietnam)
        return "lúc %02d:%02d, %02d/%02d".format(time.hour, time.minute, time.dayOfMonth, time.monthValue)
    }

    fun managerCopy(week: DutyWeekState): Copy {
        val missing = if (week.missingParticipants > 0) "${week.missingParticipants} công tác chưa có thành phần." else null
        return when (week.status) {
            "draft" -> Copy("Lịch tuần chưa nộp. Giáo viên chưa thấy lịch này.", missing ?: "Có thể bổ sung Thành phần trước khi nộp.")
            "submitted" -> Copy("Đã nộp ${moment(week.submittedAt)}. Đang chờ Ban Giám hiệu duyệt.", "Sửa lịch lúc này sẽ rút bản đã nộp về.")
            "returned" -> Copy(
                "${week.returnedByName.ifBlank { "Ban Giám hiệu" }}: “${week.returnNote}”",
                if (week.hasApprovedVersion) "Sửa xong rồi nộp lại. Giáo viên vẫn xem bản đã duyệt trước đó." else "Sửa xong rồi nộp lại. Giáo viên chưa thấy lịch tuần này.",
            )
            "approved" -> Copy(
                if (week.approvedAt != null) "${week.approvedByName.ifBlank { "Ban Giám hiệu" }} duyệt ${moment(week.approvedAt)}." else "Lịch tuần này đã có hiệu lực.",
                "Sửa lịch sẽ cần Ban Giám hiệu duyệt lại.",
            )
            "approved_changed" -> Copy("${week.changeCount} thay đổi so với bản đã duyệt. Giáo viên vẫn xem bản cũ.", missing)
            else -> Copy("Tuần này chưa có công tác.", null)
        }
    }

    fun reviewerCopy(week: DutyWeekState): Copy = when (week.status) {
        "submitted" -> Copy(
            "${week.submittedByName.ifBlank { "Văn thư" }} nộp ${moment(week.submittedAt)}.",
            "Duyệt một lần cho cả tuần · ${week.changeCount} thay đổi",
        )
        "returned" -> Copy("Đã trả lại ${moment(week.returnedAt)}: “${week.returnNote}”", "Văn thư đang sửa lại.")
        "approved" -> Copy(
            if (week.approvedAt != null) "${week.approvedByName.ifBlank { "Ban Giám hiệu" }} duyệt ${moment(week.approvedAt)}." else "Lịch tuần này đã có hiệu lực.",
            null,
        )
        "approved_changed" -> Copy("Văn thư đang sửa lịch đã duyệt.", "Giáo viên vẫn xem bản cũ cho tới khi lịch được duyệt lại.")
        "draft" -> Copy("Văn thư đang soạn lịch tuần này.", "Nút duyệt hiện khi văn thư nộp.")
        else -> Copy("Tuần này chưa có công tác.", null)
    }

    fun submitLabel(week: DutyWeekState): String = when {
        week.status == "returned" -> "Nộp lại cho BGH"
        week.hasApprovedVersion -> "Nộp duyệt lại"
        else -> "Nộp BGH duyệt"
    }

    fun canSubmit(week: DutyWeekState?, canSubmit: Boolean): Boolean =
        canSubmit && week != null && week.changeCount > 0 && week.status in setOf("draft", "returned", "approved_changed")

    fun canDecide(week: DutyWeekState?, canReview: Boolean): Boolean =
        canReview && week?.status == "submitted" && week.submittedAt != null

    /** Teachers see an empty week as "not approved yet" instead of a blank sheet. */
    fun showUnapprovedNotice(viewer: String, eventCount: Int): Boolean = viewer == "public" && eventCount == 0

    fun isWeekNotification(sourceType: String): Boolean =
        sourceType == "duty_week_review" || sourceType == "duty_week_returned" || sourceType == "duty_week_approved"
}

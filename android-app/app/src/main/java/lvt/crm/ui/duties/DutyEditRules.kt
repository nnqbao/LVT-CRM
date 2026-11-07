package lvt.crm.ui.duties

import lvt.crm.data.duties.DutyDraft
import lvt.crm.data.duties.SharedDutyEvent

/** Client-side checks that mirror `cleanDutyInput`; the server still validates everything. */
object DutyEditRules {
    const val TEXT_MAX = 200
    const val OTHER_MAX = 500

    fun draftFrom(event: SharedDutyEvent) = DutyDraft(
        id = event.id,
        title = event.title.ifBlank { event.content },
        content = event.content,
        startDate = event.startDate,
        endDate = event.endDate,
        startTime = event.startTime.ifBlank { "07:00" },
        endTime = event.endTime.ifBlank { "17:00" },
        allDay = event.allDay,
        locationText = event.locationText,
        departmentIds = event.departmentIds,
        participantUserIds = event.participantUserIds,
        otherParticipants = event.otherParticipants,
    )

    /** All-day duties keep the web's 08:00–17:00 on one day. */
    fun normalized(draft: DutyDraft): DutyDraft =
        if (draft.allDay) draft.copy(endDate = draft.startDate, startTime = "08:00", endTime = "17:00") else draft

    fun error(draft: DutyDraft): String? {
        val value = normalized(draft)
        return when {
            value.title.isBlank() || value.title.trim().length > TEXT_MAX -> "Tên công tác bắt buộc, tối đa $TEXT_MAX ký tự."
            value.content.isBlank() || value.content.trim().length > TEXT_MAX -> "Nội dung bắt buộc, tối đa $TEXT_MAX ký tự."
            value.locationText.isBlank() || value.locationText.trim().length > TEXT_MAX -> "Địa điểm bắt buộc, tối đa $TEXT_MAX ký tự."
            value.otherParticipants.trim().length > OTHER_MAX -> "Thành phần khác tối đa $OTHER_MAX ký tự."
            "${value.endDate} ${value.endTime}" < "${value.startDate} ${value.startTime}" -> "Thời gian kết thúc phải sau thời gian bắt đầu."
            else -> null
        }
    }

    fun trimmed(draft: DutyDraft): DutyDraft {
        val value = normalized(draft)
        return value.copy(
            title = value.title.trim(),
            content = value.content.trim(),
            locationText = value.locationText.trim(),
            otherParticipants = value.otherParticipants.trim(),
        )
    }

    fun dateLabel(iso: String): String {
        val parts = iso.split("-")
        return if (parts.size == 3) "${parts[2]}/${parts[1]}/${parts[0]}" else iso
    }
}

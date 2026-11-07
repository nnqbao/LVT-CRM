import Foundation

/// One row of the shared Lịch công tác (approved copy for teachers, working copy for văn thư/BGH).
struct SharedDutyEvent: Equatable, Sendable {
    let id: String
    let title: String
    let content: String
    let startDate: String
    let endDate: String
    let startTime: String
    let endTime: String
    let allDay: Bool
    let locationText: String
    let departmentIds: [String]
    let participantUserIds: [String]
    let departmentNames: [String]
    let participantNames: [String]
    let otherParticipants: String
    let canManage: Bool
    /// "added" | "changed" | nil — only for văn thư/BGH.
    let approvalChange: String?
}

struct DutyWeekChange: Equatable, Sendable {
    let id: String
    let kind: String
    let title: String
}

struct DutyWeekState: Equatable, Sendable {
    let weekStart: String
    /// empty | draft | submitted | returned | approved | approved_changed
    let status: String
    let changeCount: Int
    let changes: [DutyWeekChange]
    let missingParticipants: Int
    let hasApprovedVersion: Bool
    let submittedAt: Double?
    let submittedByName: String
    let returnedAt: Double?
    let returnedByName: String
    let returnNote: String
    let approvedAt: Double?
    let approvedByName: String
}

struct SharedDutyWeek: Equatable, Sendable {
    /// manager (văn thư) | reviewer (BGH) | public (giáo viên)
    let viewer: String
    let canSubmit: Bool
    let canReview: Bool
    let events: [SharedDutyEvent]
    let week: DutyWeekState?
}

struct DutyFormOption: Equatable, Sendable {
    let id: String
    let label: String
    let detail: String
}

struct DutyFormOptions: Equatable, Sendable {
    let isOps: Bool
    let departments: [DutyFormOption]
    let users: [DutyFormOption]
}

/// Fields `duties:update` takes; the server validates and re-checks permission.
struct DutyDraft: Equatable, Sendable {
    let id: String
    var title: String
    var content: String
    var startDate: String
    var endDate: String
    var startTime: String
    var endTime: String
    var allDay: Bool
    var locationText: String
    var departmentIds: [String]
    var participantUserIds: [String]
    var otherParticipants: String
}

/// Wording and grouping for the weekly Lịch công tác chung (same rules as the web sheet and Android).
enum DutyWeekPresentation {
    struct Copy: Equatable {
        let text: String
        let hint: String?
    }

    struct Day: Equatable {
        let iso: String
        let title: String
        let events: [SharedDutyEvent]
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        return calendar
    }

    private static let weekdays = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]

    static func date(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func iso(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func addDays(_ iso: String, _ days: Int) -> String {
        guard let date = date(iso), let next = calendar.date(byAdding: .day, value: days, to: date) else { return iso }
        return Self.iso(next)
    }

    static func todayIso(now: Date = Date()) -> String { iso(now) }

    static func weekStart(_ anchorIso: String) -> String {
        guard let date = date(anchorIso) else { return anchorIso }
        let weekday = calendar.component(.weekday, from: date)
        return addDays(anchorIso, weekday == 1 ? -6 : 2 - weekday)
    }

    static func weekEnd(_ weekStart: String) -> String { addDays(weekStart, 5) }

    static func shiftWeek(_ weekStart: String, _ direction: Int) -> String { addDays(weekStart, direction * 7) }

    private static func dayMonth(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[2])/\(parts[1])"
    }

    static func weekLabel(_ weekStart: String) -> String { "Tuần \(dayMonth(weekStart)) – \(dayMonth(weekEnd(weekStart)))" }

    static func dayTitle(_ iso: String) -> String {
        guard let date = date(iso) else { return iso }
        return "\(weekdays[calendar.component(.weekday, from: date) - 1]) \(dayMonth(iso))"
    }

    /// "14:00" → "14g00", the way the school writes it on paper.
    static func clock(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), parts[1].count == 2 else { return trimmed }
        return "\(hour)g\(parts[1])"
    }

    static func timeLabel(_ event: SharedDutyEvent) -> String {
        if event.startDate != event.endDate { return "Đến \(dayMonth(event.endDate))" }
        if event.allDay { return "Cả ngày" }
        return clock(event.startTime)
    }

    static func participants(_ event: SharedDutyEvent) -> String {
        var parts: [String] = []
        for name in event.departmentNames + event.participantNames + [event.otherParticipants] {
            let label = name.trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, !parts.contains(label) { parts.append(label) }
        }
        return parts.joined(separator: ", ")
    }

    static func hasParticipants(_ event: SharedDutyEvent) -> Bool {
        !event.departmentIds.isEmpty || !event.participantUserIds.isEmpty
            || !event.otherParticipants.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Monday to Saturday; a duty that began last week shows on Monday.
    static func days(weekStart: String, events: [SharedDutyEvent]) -> [Day] {
        let isoDays = (0...5).map { addDays(weekStart, $0) }
        var byDay: [String: [SharedDutyEvent]] = [:]
        for event in events {
            guard event.endDate >= isoDays[0], event.startDate <= isoDays[5] else { continue }
            let day = event.startDate < isoDays[0] ? isoDays[0] : event.startDate
            byDay[day, default: []].append(event)
        }
        func key(_ event: SharedDutyEvent) -> String {
            event.allDay || event.startDate != event.endDate ? "0" : "1-\(event.startTime)"
        }
        return isoDays.map { iso in
            let sorted = (byDay[iso] ?? []).sorted { key($0) == key($1) ? $0.title < $1.title : key($0) < key($1) }
            return Day(iso: iso, title: dayTitle(iso), events: sorted)
        }
    }

    static func pill(_ status: String) -> String {
        switch status {
        case "draft": return "Nháp"
        case "submitted": return "Chờ duyệt"
        case "returned": return "Bị trả lại"
        case "approved": return "Đã duyệt"
        case "approved_changed": return "Đã duyệt · có thay đổi chờ duyệt"
        default: return "Chưa có lịch"
        }
    }

    static func tone(_ status: String) -> HomeroomTone {
        switch status {
        case "submitted", "approved_changed": return .warning
        case "returned": return .danger
        case "approved": return .success
        default: return .neutral
        }
    }

    static func changeLabel(_ kind: String) -> String {
        switch kind {
        case "added": return "Thêm"
        case "removed": return "Xóa"
        case "moved_out": return "Chuyển tuần"
        default: return "Sửa"
        }
    }

    /// "lúc 10:20, 17/10" in Vietnam time.
    static func moment(_ ms: Double?) -> String {
        guard let ms, ms > 0 else { return "" }
        let parts = calendar.dateComponents([.hour, .minute, .day, .month], from: Date(timeIntervalSince1970: ms / 1000))
        return String(format: "lúc %02d:%02d, %02d/%02d", parts.hour ?? 0, parts.minute ?? 0, parts.day ?? 0, parts.month ?? 0)
    }

    private static func approver(_ week: DutyWeekState) -> String {
        week.approvedByName.isEmpty ? "Ban Giám hiệu" : week.approvedByName
    }

    static func managerCopy(_ week: DutyWeekState) -> Copy {
        let missing = week.missingParticipants > 0 ? "\(week.missingParticipants) công tác chưa có thành phần." : nil
        switch week.status {
        case "draft":
            return Copy(text: "Lịch tuần chưa nộp. Giáo viên chưa thấy lịch này.", hint: missing ?? "Có thể bổ sung Thành phần trước khi nộp.")
        case "submitted":
            return Copy(text: "Đã nộp \(moment(week.submittedAt)). Đang chờ Ban Giám hiệu duyệt.", hint: "Sửa lịch lúc này sẽ rút bản đã nộp về.")
        case "returned":
            let who = week.returnedByName.isEmpty ? "Ban Giám hiệu" : week.returnedByName
            return Copy(
                text: "\(who): “\(week.returnNote)”",
                hint: week.hasApprovedVersion
                    ? "Sửa xong rồi nộp lại. Giáo viên vẫn xem bản đã duyệt trước đó."
                    : "Sửa xong rồi nộp lại. Giáo viên chưa thấy lịch tuần này."
            )
        case "approved":
            return Copy(
                text: week.approvedAt != nil ? "\(approver(week)) duyệt \(moment(week.approvedAt))." : "Lịch tuần này đã có hiệu lực.",
                hint: "Sửa lịch sẽ cần Ban Giám hiệu duyệt lại."
            )
        case "approved_changed":
            return Copy(text: "\(week.changeCount) thay đổi so với bản đã duyệt. Giáo viên vẫn xem bản cũ.", hint: missing)
        default:
            return Copy(text: "Tuần này chưa có công tác.", hint: nil)
        }
    }

    static func reviewerCopy(_ week: DutyWeekState) -> Copy {
        switch week.status {
        case "submitted":
            let who = week.submittedByName.isEmpty ? "Văn thư" : week.submittedByName
            return Copy(text: "\(who) nộp \(moment(week.submittedAt)).", hint: "Duyệt một lần cho cả tuần · \(week.changeCount) thay đổi")
        case "returned":
            return Copy(text: "Đã trả lại \(moment(week.returnedAt)): “\(week.returnNote)”", hint: "Văn thư đang sửa lại.")
        case "approved":
            return Copy(text: week.approvedAt != nil ? "\(approver(week)) duyệt \(moment(week.approvedAt))." : "Lịch tuần này đã có hiệu lực.", hint: nil)
        case "approved_changed":
            return Copy(text: "Văn thư đang sửa lịch đã duyệt.", hint: "Giáo viên vẫn xem bản cũ cho tới khi lịch được duyệt lại.")
        case "draft":
            return Copy(text: "Văn thư đang soạn lịch tuần này.", hint: "Nút duyệt hiện khi văn thư nộp.")
        default:
            return Copy(text: "Tuần này chưa có công tác.", hint: nil)
        }
    }

    static func submitLabel(_ week: DutyWeekState) -> String {
        if week.status == "returned" { return "Nộp lại cho BGH" }
        return week.hasApprovedVersion ? "Nộp duyệt lại" : "Nộp BGH duyệt"
    }

    static func canSubmit(_ week: DutyWeekState?, canSubmit: Bool) -> Bool {
        guard canSubmit, let week, week.changeCount > 0 else { return false }
        return ["draft", "returned", "approved_changed"].contains(week.status)
    }

    static func canDecide(_ week: DutyWeekState?, canReview: Bool) -> Bool {
        canReview && week?.status == "submitted" && week?.submittedAt != nil
    }

    /// Teachers see an empty week as "not approved yet" instead of a blank sheet.
    static func showUnapprovedNotice(viewer: String, eventCount: Int) -> Bool { viewer == "public" && eventCount == 0 }

    static func isWeekNotification(_ sourceType: String) -> Bool {
        ["duty_week_review", "duty_week_returned", "duty_week_approved"].contains(sourceType)
    }
}

/// Client-side checks that mirror `cleanDutyInput`; the server still validates everything.
enum DutyEditRules {
    static let textMax = 200
    static let otherMax = 500

    static func draft(from event: SharedDutyEvent) -> DutyDraft {
        DutyDraft(
            id: event.id,
            title: event.title.isEmpty ? event.content : event.title,
            content: event.content,
            startDate: event.startDate,
            endDate: event.endDate,
            startTime: event.startTime.isEmpty ? "07:00" : event.startTime,
            endTime: event.endTime.isEmpty ? "17:00" : event.endTime,
            allDay: event.allDay,
            locationText: event.locationText,
            departmentIds: event.departmentIds,
            participantUserIds: event.participantUserIds,
            otherParticipants: event.otherParticipants
        )
    }

    /// All-day duties keep the web's 08:00–17:00 on one day.
    static func normalized(_ draft: DutyDraft) -> DutyDraft {
        guard draft.allDay else { return draft }
        var value = draft
        value.endDate = value.startDate
        value.startTime = "08:00"
        value.endTime = "17:00"
        return value
    }

    private static func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private static func length(_ text: String) -> Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    static func error(_ draft: DutyDraft) -> String? {
        let value = normalized(draft)
        if blank(value.title) || length(value.title) > textMax { return "Tên công tác bắt buộc, tối đa \(textMax) ký tự." }
        if blank(value.content) || length(value.content) > textMax { return "Nội dung bắt buộc, tối đa \(textMax) ký tự." }
        if blank(value.locationText) || length(value.locationText) > textMax { return "Địa điểm bắt buộc, tối đa \(textMax) ký tự." }
        if length(value.otherParticipants) > otherMax { return "Thành phần khác tối đa \(otherMax) ký tự." }
        if "\(value.endDate) \(value.endTime)" < "\(value.startDate) \(value.startTime)" {
            return "Thời gian kết thúc phải sau thời gian bắt đầu."
        }
        return nil
    }

    static func trimmed(_ draft: DutyDraft) -> DutyDraft {
        var value = normalized(draft)
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.content = value.content.trimmingCharacters(in: .whitespacesAndNewlines)
        value.locationText = value.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        value.otherParticipants = value.otherParticipants.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    static func selectionLabel(_ kind: String, ids: [String], options: [DutyFormOption]) -> String {
        if ids.isEmpty { return "\(kind): chưa chọn" }
        let names = options.filter { ids.contains($0.id) }.map(\.label)
        if names.count <= 2 { return "\(kind): \(names.joined(separator: ", "))" }
        return "\(kind): \(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)"
    }
}

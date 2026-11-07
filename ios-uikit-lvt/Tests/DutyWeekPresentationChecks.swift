import Foundation

@main
struct DutyWeekPresentationChecks {
    static func main() {
        func event(_ id: String = "d1", start: String = "2026-10-20", end: String? = nil, time: String = "14:00", allDay: Bool = false, other: String = "") -> SharedDutyEvent {
            SharedDutyEvent(
                id: id, title: "Họp tổ Toán", content: "Họp tổ Toán", startDate: start, endDate: end ?? start,
                startTime: time, endTime: "16:00", allDay: allDay, locationText: "Phòng họp 1",
                departmentIds: [], participantUserIds: [], departmentNames: ["Tổ Toán"], participantNames: [],
                otherParticipants: other, canManage: true, approvalChange: nil
            )
        }
        func week(_ status: String, changes: Int = 1, approved: Bool = false) -> DutyWeekState {
            DutyWeekState(
                weekStart: "2026-10-19", status: status, changeCount: changes, changes: [], missingParticipants: 0,
                hasApprovedVersion: approved, submittedAt: 1.79e12, submittedByName: "Cô Hoa", returnedAt: nil,
                returnedByName: "", returnNote: "", approvedAt: nil, approvedByName: ""
            )
        }

        precondition(DutyWeekPresentation.weekStart("2026-10-25") == "2026-10-19")
        precondition(DutyWeekPresentation.weekStart("2026-10-19") == "2026-10-19")
        precondition(DutyWeekPresentation.weekEnd("2026-10-19") == "2026-10-24")
        precondition(DutyWeekPresentation.shiftWeek("2026-10-19", 1) == "2026-10-26")
        precondition(DutyWeekPresentation.weekLabel("2026-10-19") == "Tuần 19/10 – 24/10")
        precondition(DutyWeekPresentation.dayTitle("2026-10-20") == "Thứ Ba 20/10")

        let days = DutyWeekPresentation.days(
            weekStart: "2026-10-19",
            events: [event("a"), event("b", start: "2026-10-16", end: "2026-10-20", allDay: true)]
        )
        precondition(days.count == 6)
        precondition(days[0].events.map(\.id) == ["b"])
        precondition(days[1].events.map(\.id) == ["a"])
        precondition(days[5].events.isEmpty)

        precondition(DutyWeekPresentation.timeLabel(event()) == "14g00")
        precondition(DutyWeekPresentation.clock("07:30") == "7g30")
        precondition(DutyWeekPresentation.timeLabel(event(allDay: true)) == "Cả ngày")
        precondition(DutyWeekPresentation.timeLabel(event(end: "2026-10-22")) == "Đến 22/10")
        precondition(DutyWeekPresentation.moment(1_791_602_400_000) == "lúc 10:20, 10/10")

        precondition(DutyWeekPresentation.participants(event(other: "Khách mời")) == "Tổ Toán, Khách mời")
        precondition(!DutyWeekPresentation.hasParticipants(event()))
        precondition(DutyWeekPresentation.hasParticipants(event(other: "BGH")))

        precondition(DutyWeekPresentation.canSubmit(week("draft"), canSubmit: true))
        precondition(!DutyWeekPresentation.canSubmit(week("draft"), canSubmit: false))
        precondition(!DutyWeekPresentation.canSubmit(week("submitted"), canSubmit: true))
        precondition(!DutyWeekPresentation.canSubmit(week("approved", changes: 0), canSubmit: true))
        precondition(DutyWeekPresentation.canDecide(week("submitted"), canReview: true))
        precondition(!DutyWeekPresentation.canDecide(week("returned"), canReview: true))
        precondition(DutyWeekPresentation.submitLabel(week("returned")) == "Nộp lại cho BGH")
        precondition(DutyWeekPresentation.submitLabel(week("approved_changed", approved: true)) == "Nộp duyệt lại")
        precondition(DutyWeekPresentation.submitLabel(week("draft")) == "Nộp BGH duyệt")

        precondition(DutyWeekPresentation.showUnapprovedNotice(viewer: "public", eventCount: 0))
        precondition(!DutyWeekPresentation.showUnapprovedNotice(viewer: "manager", eventCount: 0))
        precondition(DutyWeekPresentation.pill("approved_changed") == "Đã duyệt · có thay đổi chờ duyệt")
        precondition(DutyWeekPresentation.isWeekNotification("duty_week_review"))
        precondition(!DutyWeekPresentation.isWeekNotification("duty_assigned"))

        var draft = DutyEditRules.draft(from: event())
        precondition(DutyEditRules.error(draft) == nil)
        draft.locationText = " "
        precondition(DutyEditRules.error(draft) == "Địa điểm bắt buộc, tối đa 200 ký tự.")
        draft = DutyEditRules.draft(from: event())
        draft.endTime = "13:00"
        precondition(DutyEditRules.error(draft) == "Thời gian kết thúc phải sau thời gian bắt đầu.")
        draft = DutyEditRules.draft(from: event())
        draft.allDay = true
        draft.endDate = "2026-10-23"
        let allDay = DutyEditRules.trimmed(draft)
        precondition(allDay.endDate == "2026-10-20" && allDay.startTime == "08:00" && allDay.endTime == "17:00")

        precondition(ConvexHttpClient.humanize("Uncaught Error: INVALID_CONTENT") == "Nội dung công tác bắt buộc, tối đa 200 ký tự.")
        precondition(ConvexHttpClient.humanize("Uncaught Error: DUTY_WEEK_CHANGED") == "Văn thư vừa sửa lịch tuần này. Hãy xem lại trước khi duyệt.")
        print("DutyWeekPresentationChecks: OK")
    }
}

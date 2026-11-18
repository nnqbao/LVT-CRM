import Foundation

@main
struct HomeroomPresentationChecks {
    static func main() throws {
        func counts(present: Int = 0, late: Int = 0, absent: Int = 0, noData: Int = 0, exempt: Int = 0) -> AttendanceCounts {
            AttendanceCounts(present: present, late: late, absentExcused: 0, absentUnexcused: 0, absentPending: absent, noData: noData, exempt: exempt)
        }
        func klass(_ counts: AttendanceCounts, published: Bool = true, pending: Int = 0, teacher: String = "Lê Thị Cúc", name: String = "Lớp 6-2") -> HomeroomClassSummary {
            HomeroomClassSummary(id: "c1", code: "2627-6-2", name: name, gradeLevel: 6, rosterCount: 41, teacherName: teacher, published: published, counts: counts, pendingTotal: pending, canCorrect: true)
        }
        precondition(HomeroomPresentation.classTitle(klass(counts())) == "Lớp 6-2")
        precondition(HomeroomPresentation.classTitle(klass(counts(), name: "")) == "Lớp 2627-6-2")
        precondition(HomeroomPresentation.classSubtitle(klass(counts())) == "41 HS · Lê Thị Cúc")
        precondition(HomeroomPresentation.classSubtitle(klass(counts(), teacher: "")) == "41 HS · Chưa có GVCN")
        precondition(HomeroomPresentation.classChips(klass(counts(present: 41)), schoolDay: true) == [HomeroomChip(text: "Đủ 41/41", tone: .success)])
        precondition(HomeroomPresentation.classChips(klass(counts(present: 37, late: 1, absent: 3), pending: 2), schoolDay: true)
            == [HomeroomChip(text: "3 vắng", tone: .danger), HomeroomChip(text: "2 chờ", tone: .warning)])
        precondition(HomeroomPresentation.classChips(klass(counts(present: 40, late: 1)), schoolDay: true) == [HomeroomChip(text: "1 trễ", tone: .warning)])
        precondition(HomeroomPresentation.classChips(klass(counts(), published: false), schoolDay: true) == [HomeroomChip(text: "Chưa điểm danh", tone: .neutral)])
        precondition(HomeroomPresentation.classChips(klass(counts(), published: false), schoolDay: false).isEmpty)
        // Full wording per status (never colour only); legacy Đi trễ / Vắng chờ xử lý still render.
        precondition(HomeroomPresentation.studentChip(status: "present", observedTime: nil) == HomeroomChip(text: "Có mặt", tone: .success))
        precondition(HomeroomPresentation.studentChip(status: "absent_excused", observedTime: nil) == HomeroomChip(text: "Vắng có phép", tone: .info))
        precondition(HomeroomPresentation.studentChip(status: "absent_unexcused", observedTime: nil) == HomeroomChip(text: "Vắng không phép", tone: .danger))
        precondition(HomeroomPresentation.studentChip(status: "absent_pending", observedTime: nil) == HomeroomChip(text: "Vắng chờ xử lý", tone: .warning))
        precondition(HomeroomPresentation.studentChip(status: "late", observedTime: "07:12") == HomeroomChip(text: "Đi trễ 07:12", tone: .warning))
        precondition(HomeroomDetailDecoder.statusText("late") == "Đi trễ" && HomeroomDetailDecoder.statusText("absent_pending") == "Vắng chờ xử lý" && HomeroomDetailDecoder.statusText("bogus") == "Trạng thái không hợp lệ")
        precondition(HomeroomPresentation.studentChip(status: "no_data", observedTime: nil) == HomeroomChip(text: "Chưa có", tone: .neutral))
        let stats = HomeroomPresentation.overviewStats(counts(present: 2301, late: 18, absent: 12, noData: 7))
        precondition(stats.map(\.value) == ["2.301", "18", "12", "7"])
        precondition(stats.map(\.label) == ["Có mặt", "Trễ", "Vắng", "Chưa có"])
        precondition(HomeroomPresentation.overviewSummary(studentCount: 2338, classCount: 50, attendanceRate: 0.984, ratedRows: 10) == "Chuyên cần 98,4% · 50 lớp · 2.338 học sinh")
        precondition(HomeroomPresentation.overviewSummary(studentCount: 2338, classCount: 50, attendanceRate: 0, ratedRows: 0) == "50 lớp · 2.338 học sinh")
        let daily = HomeroomPresentation.dailyStats(["present", "late", "absent_excused", "absent_unexcused", "absent_unexcused"])
        precondition(daily.map(\.label) == ["Có mặt", "Vắng có phép", "Vắng không phép"] && daily.map(\.value) == ["2", "1", "2"])
        precondition(HomeroomPresentation.dailyStats(["present", "absent_pending"]).map(\.label) == ["Có mặt", "Vắng có phép", "Vắng không phép", "Vắng chờ xử lý"])
        precondition(HomeroomPresentation.dailyStats(["present", "no_data"]).last?.label == "Chưa có")

        // GVCN class day: absentees first (roster order kept), toggle state, "not marked" wording.
        func row(_ id: String, raw: String?, disposition: String = "none", status: String = "present") throws -> DailyRow {
            var value: [String: Any] = ["enrollment": ["_id": "e-\(id)"], "student": ["_id": id, "studentCode": "S-\(id)", "fullName": "HS \(id)"], "day": NSNull()]
            if let raw { value["day"] = ["_id": "d-\(id)", "rawObservation": raw, "disposition": disposition, "effectiveStatus": status] }
            return try JSONDecoder().decode(DailyRow.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let rows = try [
            row("1", raw: "present"),
            row("2", raw: "absent", disposition: "excused", status: "absent_excused"),
            row("3", raw: nil),
            row("4", raw: "absent", disposition: "unexcused", status: "absent_unexcused"),
            row("5", raw: "absent", disposition: "pending", status: "absent_pending"),
        ]
        let split = HomeroomPresentation.splitAttendance(rows)
        precondition(split.absent.map(\.student._id) == ["2", "4", "5"] && split.others.map(\.student._id) == ["1", "3"])
        precondition(!HomeroomPresentation.isUnexcused(rows[1].day) && HomeroomPresentation.isUnexcused(rows[3].day) && !HomeroomPresentation.isUnexcused(rows[4].day))
        func classDay(published: Bool, saved: Bool) throws -> ClassDaily {
            var value: [String: Any] = ["date": "2026-10-09", "rows": [], "published": published, "archived": false, "canCorrect": true, "schoolDay": ["isSchoolDay": true, "kind": "school_day", "outsideYear": false]]
            if saved { value["classSaved"] = ["savedAt": 1791333720000, "savedByName": "Giám thị A", "source": "manual", "absentCount": 2] }
            return try HomeroomDetailDecoder.daily(value)
        }
        let unmarked = try classDay(published: false, saved: false)
        let markedNoAbsence = try classDay(published: false, saved: true)
        let legacyPublished = try classDay(published: true, saved: false)
        precondition(HomeroomPresentation.classNotMarked(unmarked))
        precondition(!HomeroomPresentation.classNotMarked(markedNoAbsence))
        precondition(!HomeroomPresentation.classNotMarked(legacyPublished) && legacyPublished.classSaved == nil)
        let saved = try classDay(published: true, saved: true).classSaved!
        precondition(saved.absentCount == 2 && HomeroomPresentation.savedByText(saved) == "Giám thị lưu lúc \(HomeroomPresentation.clock(1791333720000)) · Giám thị A")
        precondition(HomeroomPresentation.notMarkedMessage(date: "2026-10-09", today: "2026-10-09") == "Giám thị chưa điểm danh lớp này hôm nay.")
        precondition(HomeroomPresentation.notMarkedMessage(date: "2026-10-08", today: "2026-10-09") == "Giám thị chưa điểm danh lớp này ngày 08/10/2026.")
        precondition(HomeroomPresentation.dayTitle("2026-10-09") == "Thứ Sáu, 09/10")
        precondition(HomeroomPresentation.dayTitle("2026-10-11") == "Chủ Nhật, 11/10")
        precondition(HomeroomPresentation.shiftDay("2026-10-09", by: 1) == "2026-10-10")
        precondition(HomeroomPresentation.shiftDay("2026-10-01", by: -1) == "2026-09-30")
        precondition(HomeroomPresentation.dayTitle("not-a-date") == "not-a-date")
        print("HomeroomPresentationChecks passed")
    }
}

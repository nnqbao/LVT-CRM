// extra-sources: Boarding
import Foundation

/// Offline checks for Báo cáo › Bán trú (2.1.0): `boarding:report` / `boarding:listAdmin` decoding, the shared
/// "Học kỳ N · Năm học …" label, visibility (Báo cáo level / admin-mod), school-year options, form validation,
/// payloads and Vietnamese error wording. Injected fixtures only: no network, credentials or app launch.
@main
struct BoardingChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
        func rejects(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); check(false, message) } catch { check(true, message) }
        }

        // Labels (web boardingPeriodLabel).
        check(Boarding.periodLabel(semester: 1, schoolYear: "2026-2027") == "Học kỳ 1 · Năm học 2026-2027", "Full label")
        check(Boarding.periodLabel(semester: 2, schoolYear: "2026-2027", short: true) == "Học kỳ 2", "Short label")
        check(Boarding.periodLabel(semester: 1, schoolYear: "") == "Học kỳ 1", "No year")
        check(Boarding.periodLabel(nil) == "Chưa có kỳ bán trú", "No period")

        // Report decoding.
        let person: [String: Any] = ["_id": "u1", "name": "Cô Lan", "email": "lan@x", "departmentName": "Tổ Toán", "positionName": "Giáo viên"]
        let reportRow: [String: Any] = [
            "visibilityScope": "department",
            "periods": [
                ["_id": "p2", "semester": 2, "schoolYear": "2026-2027", "participantCount": 5],
                ["_id": "p1", "semester": 1, "schoolYear": "2026-2027", "participantCount": 3],
            ],
            "selectedPeriod": ["_id": "p2", "semester": 2, "schoolYear": "2026-2027"],
            "groups": [["departmentName": "Tổ Toán", "participants": [person], "participantCount": 1]],
            "totalParticipants": 1,
        ]
        do {
            let report = try Boarding.decodeReport(reportRow)
            check(!report.isSchoolWide && report.periods.map(\.id) == ["p2", "p1"], "Department scope + period order")
            check(report.selectedPeriod?.id == "p2" && report.selectedPeriod?.participantCount == 5, "Selected period reuses list row")
            check(report.groups.count == 1 && report.groups[0].participants[0].name == "Cô Lan" && report.totalParticipants == 1, "Groups")
            check(Boarding.scopeText(report) == "Bạn đang xem giáo viên tham gia bán trú trong phòng ban của mình.", "Department wording")
            check(Boarding.hasPeriod(forSchoolYear: "2026-2027", in: report.periods) && !Boarding.hasPeriod(forSchoolYear: "2027-2028", in: report.periods), "Current-year period")
        } catch { check(false, "Valid report decodes") }
        var empty = reportRow
        empty["visibilityScope"] = "all"
        empty["periods"] = [[String: Any]]()
        empty["selectedPeriod"] = NSNull()
        empty["groups"] = [[String: Any]]()
        empty["totalParticipants"] = 0
        do {
            let report = try Boarding.decodeReport(empty)
            check(report.isSchoolWide && report.selectedPeriod == nil && report.periods.isEmpty, "Empty report (no period)")
            check(Boarding.scopeText(report) == "Bạn đang xem toàn bộ phòng ban tham gia bán trú.", "School-wide wording")
        } catch { check(false, "Empty report decodes") }
        var bad = reportRow
        bad["visibilityScope"] = "everyone"
        rejects({ _ = try Boarding.decodeReport(bad) }, "Unknown scope")
        bad = reportRow
        bad["periods"] = [["_id": "p", "semester": 3, "schoolYear": "2026-2027"]]
        rejects({ _ = try Boarding.decodeReport(bad) }, "Semester 3")
        bad = reportRow
        bad["periods"] = [["_id": "p", "semester": 1, "schoolYear": "2026-2028"]]
        rejects({ _ = try Boarding.decodeReport(bad) }, "Non-consecutive year")
        bad = reportRow
        bad["periods"] = [["_id": "", "semester": 1, "schoolYear": "2026-2027"]]
        rejects({ _ = try Boarding.decodeReport(bad) }, "Empty id")
        bad = reportRow
        bad["periods"] = [["_id": "p", "semester": true, "schoolYear": "2026-2027"]]
        rejects({ _ = try Boarding.decodeReport(bad) }, "Boolean semester")
        bad = reportRow
        bad["selectedPeriod"] = "p2"
        rejects({ _ = try Boarding.decodeReport(bad) }, "Malformed selected period")
        bad = reportRow
        bad.removeValue(forKey: "groups")
        rejects({ _ = try Boarding.decodeReport(bad) }, "Missing groups")

        // Admin decoding.
        do {
            let admin = try Boarding.decodeAdmin([
                "users": [person],
                "periods": [["_id": "p1", "semester": 1, "schoolYear": "2026-2027", "participantUserIds": ["u1"], "participants": [person], "active": true]],
            ])
            check(admin.users.map(\.id) == ["u1"] && admin.periods[0].participantUserIds == ["u1"] && admin.periods[0].participants.count == 1, "Admin data")
            check(Boarding.deletePrompt(admin.periods[0]) == "Xóa Học kỳ 1 · Năm học 2026-2027?", "Delete confirmation")
        } catch { check(false, "Admin decodes") }
        rejects({ _ = try Boarding.decodeAdmin(["users": [], "periods": [["_id": "p1", "semester": 1, "schoolYear": "2026-2027"]]]) }, "Missing participant ids")

        // Visibility: Báo cáo level (view / view_all) or admin/mod; management only admin/mod.
        func session(role: String = "user", reports: MenuAccess? = nil, status: String = "active", mustChange: Bool = false) -> UserSession {
            UserSession(
                userId: "u", email: "u@x", name: "U", role: role, status: status, mustChangePassword: mustChange,
                departmentName: nil, positionName: nil, positionLevel: 1, hasAvatar: false, avatarVersion: nil,
                menuAccess: reports.map { ["reports": $0] } ?? [:]
            )
        }
        check(Boarding.canSeeParticipants(session(reports: .view)) && Boarding.canSeeParticipants(session(reports: .viewAll)), "Báo cáo view / view_all")
        check(!Boarding.canSeeParticipants(session(reports: .hidden)) && !Boarding.canSeeParticipants(session()), "Báo cáo hidden")
        check(Boarding.canSeeParticipants(session(role: "moderator")) && Boarding.canManagePeriods(session(role: "admin")), "Admin/mod")
        check(!Boarding.canManagePeriods(session(reports: .viewAll)), "Users never manage")
        check(!Boarding.canSeeParticipants(session(reports: .view, mustChange: true)) && !Boarding.canSeeParticipants(session(role: "admin", status: "disabled")), "Inactive or password change")
        let decoded = UserSession(sessionContext: ["user": ["_id": "u", "role": "user", "status": "active"], "menuAccess": ["reports": "supervisor"]])
        check(decoded.map { !Boarding.canSeeParticipants($0) } == true, "Supervisor is not valid on reports")

        // School years (Vietnam time: July starts a new year).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        let october = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!
        check(Boarding.currentSchoolYear(now: october) == "2026-2027" && Boarding.currentSchoolYear(now: june) == "2025-2026", "Current school year")
        check(Boarding.schoolYearOptions(now: october) == ["2024-2025", "2025-2026", "2026-2027", "2027-2028", "2028-2029", "2029-2030", "2030-2031"], "Year options")
        check(Boarding.schoolYearOptions(now: october, including: "2019-2020").first == "2019-2020", "Editing keeps an old year")
        check(Boarding.emptyForm(now: october) == BoardingForm(semester: 1, schoolYear: "2026-2027", participantUserIds: []), "Empty form")

        // Validation + payloads.
        var form = BoardingForm(semester: 1, schoolYear: "2026-2027", participantUserIds: [])
        check(Boarding.validate(form) == "Vui lòng chọn ít nhất một giáo viên.", "Teachers required")
        form.participantUserIds = [" u1 ", "u1", "", "u2"]
        check(Boarding.validate(form) == nil, "Valid form")
        form.semester = 3
        check(Boarding.validate(form) == "Học kỳ chỉ được chọn 1 hoặc 2.", "Semester")
        form.semester = 2
        form.schoolYear = "2026-2026"
        check(Boarding.validate(form) == "Năm học không hợp lệ.", "School year")
        form.schoolYear = "2026-2027"
        let create = Boarding.mutationArgs(form)
        check(create["semester"] as? Int == 2 && create["schoolYear"] as? String == "2026-2027" && create["participantUserIds"] as? [String] == ["u1", "u2"] && create["id"] == nil, "Create args")
        check(Boarding.mutationArgs(form, id: "p1")["id"] as? String == "p1", "Update args")
        check(BoardingEndpoint.report == "boarding:report" && BoardingEndpoint.listAdmin == "boarding:listAdmin" && BoardingEndpoint.create == "boarding:create" && BoardingEndpoint.update == "boarding:update" && BoardingEndpoint.remove == "boarding:remove", "Endpoints")

        // Errors (web BoardingManagement wording), never the generic FORBIDDEN text for boarding codes.
        let expected: [(String, String)] = [
            ("INVALID_SEMESTER", "Học kỳ chỉ được chọn 1 hoặc 2."),
            ("INVALID_SCHOOL_YEAR", "Năm học không hợp lệ."),
            ("BOARDING_TEACHERS_REQUIRED", "Vui lòng chọn ít nhất một giáo viên."),
            ("INVALID_BOARDING_TEACHER", "Có giáo viên không hợp lệ hoặc đã ngưng hoạt động."),
            ("BOARDING_PERIOD_EXISTS", "Kỳ bán trú này đã tồn tại."),
            ("BOARDING_PERIOD_NOT_FOUND", "Không tìm thấy kỳ bán trú."),
            ("BOARDING_PERIOD_FORBIDDEN", "Bạn không có quyền xem kỳ bán trú này."),
        ]
        for (code, message) in expected {
            let raw = "[CONVEX M(boarding:create)] Uncaught Error: \(code)"
            check(ConvexHttpClient.extractCode(raw) == code && ConvexHttpClient.humanize(raw) == message, "Wording \(code)")
            check(Boarding.errorMessage(ConvexException(code: ConvexHttpClient.extractCode(raw), message: ConvexHttpClient.humanize(raw))) == message, "Screen wording \(code)")
        }
        check(Boarding.errorMessage(ConvexException(code: "NETWORK", message: "x")) == "Không thể hoàn tất thao tác. Vui lòng thử lại.", "Web fallback")
        check(Boarding.errorMessage(ConvexException(code: "FORBIDDEN", message: "x")) == "Bạn không có quyền xem Bán trú.", "Reports hidden")

        print("BoardingChecks: \(checks) checks passed")
    }
}

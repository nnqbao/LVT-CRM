import Foundation

@main
struct HomeroomChecks {
    static func main() throws {
        func session(_ access: Any? = nil, attendance: Any? = nil, work: Any? = "view", role: String = "user", status: String = "active", password: Bool = false) -> UserSession {
            UserSession(sessionContext: ["user": ["_id": "test-user", "role": role, "status": status, "mustChangePassword": password],
                                         "menuAccess": ["homeroom": access ?? NSNull(), "attendance": attendance ?? NSNull(), "work": work ?? NSNull()]])!
        }
        for access: Any in [NSNull(), "unknown", true, 1, ["bad": "view"]] {
            precondition(!session(access).canSeeHomeroom)
        }
        precondition(session("edit").homeroomAccess == .view)
        precondition(session("view_all").canSeeHomeroom && !session("view_all").isAttendanceSupervisor)
        // Giám thị lives only on the `attendance` menu now: homeroom=supervisor resolves to hidden.
        precondition(session("supervisor").homeroomAccess == .hidden && !session("supervisor").canSeeHomeroom)
        precondition(!session("supervisor").canSeeAttendance && !session("supervisor").isAttendanceSupervisor)
        let supervisor = session(attendance: "supervisor")
        precondition(supervisor.isAttendanceSupervisor && supervisor.canSeeAttendance && !supervisor.canSeeHomeroom)
        // `attendance` accepts only hidden/supervisor; view/view_all/edit there resolve to hidden.
        for level in ["view", "view_all", "edit", "unknown"] { precondition(!session(attendance: level).canSeeAttendance) }
        precondition(session(attendance: "view").attendanceAccess == .hidden)
        precondition(!session(attendance: "supervisor", status: "inactive").canSeeAttendance)
        precondition(!session(attendance: "supervisor", password: true).canSeeAttendance)
        precondition(session(role: "admin").canSeeAttendance && !session(role: "admin").isAttendanceSupervisor)
        precondition(session(role: "moderator").canSeeAttendance)
        precondition(session("view", attendance: "supervisor").canSeeHomeroom && session("view", attendance: "supervisor").canSeeAttendance)
        // Work hub: ordinary users with work hidden see only "Việc của tôi"; managers always see work.
        precondition(session(work: "hidden").isWorkMenuHidden && session(work: nil).isWorkMenuHidden && session(work: "supervisor").isWorkMenuHidden)
        precondition(!session(work: "view").isWorkMenuHidden && !session(work: "hidden", role: "admin").isWorkMenuHidden)
        precondition(session(role: "admin").canSeeHomeroom)
        precondition(session(role: "moderator").canSeeHomeroom)
        precondition(!session(role: "admin", status: "inactive").canSeeHomeroom)
        let missingMenu = UserSession(sessionContext: ["user": ["_id": "test-user", "status": "active"]])!
        let malformedMenu = UserSession(sessionContext: ["user": ["_id": "test-user", "status": "active"], "menuAccess": ["view"]])!
        precondition(!missingMenu.canSeeHomeroom && !malformedMenu.canSeeHomeroom)
        precondition(!session("view", status: "inactive").canSeeHomeroom)
        precondition(!session(role: "admin", password: true).canSeeHomeroom)
        let instant = ISO8601DateFormatter().date(from: "2026-10-07T17:00:00Z")!
        precondition(VietnamDate.today(now: instant) == "2026-10-08")
        precondition(VietnamDate.today(now: instant.addingTimeInterval(-1)) == "2026-10-07")
        precondition(VietnamDate.date(from: "2024-02-29") != nil)
        for date in ["2026-02-29", "2026-02-30", "2026-13-01", "2026-1-01", "bad"] {
            precondition(VietnamDate.date(from: date) == nil)
        }
        let overview = try HomeroomRepository.decodeOverview([
            "date": "2026-10-07", "today": "2026-10-07", "mode": "teacher",
            "schoolYear": ["_id": "test-year", "name": "2026–2027"], "classes": [[String: Any]](),
            "schoolDay": [String: Any](), "missingUpload": [String: Any](),
            "summary": ["counts": ["present": 0, "late": 0, "absent_excused": 0, "absent_unexcused": 0, "no_data": 3, "absent_pending": 2, "exempt": 0], "ratedRows": 2, "totalRows": 5]
        ])
        precondition(overview.counts.noData == 3 && overview.counts.absent == 2 && overview.classes.isEmpty)
        let years = try HomeroomRepository.decodeSchoolYears(["items": [[String: Any]]()])
        precondition(years.isEmpty)
        func rejects(_ decode: () throws -> Void) {
            do { try decode(); preconditionFailure("Malformed response accepted") } catch {}
        }
        rejects { _ = try HomeroomRepository.decodeOverview([:]) }
        rejects { _ = try HomeroomRepository.decodeSchoolYears([:]) }
        print("PASS: actual UIKit source checks — role denial, Giám thị only on attendance, work-hidden hub, Vietnam dates, no_data, empty, malformed payloads; no live requests")
    }
}

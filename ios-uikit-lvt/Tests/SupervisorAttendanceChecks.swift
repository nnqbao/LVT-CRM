import Foundation

/// Offline checks for the Điểm danh (Giám thị) models, local editing state and repository.
/// Injected query/mutation fixtures only: no network, credentials or app launch.
@main
struct SupervisorAttendanceChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
        func rejects(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); check(false, message) } catch { check(true, message) }
        }

        let savedAt = 1791333720000.0 // 2026-10-07 07:42 Asia/Ho_Chi_Minh
        func klass(_ id: String, grade: Int, saved: Bool, absent: [String] = []) -> [String: Any] {
            [
                "classId": id, "code": "2627-\(id)", "name": id, "gradeLevel": grade,
                "saved": saved ? ["savedAt": savedAt, "savedByName": "Giám thị A", "source": "manual", "presentCount": 2, "absentCount": absent.count] as [String: Any] : NSNull(),
                "students": ["s1", "s2", "s3"].map { ["studentId": "\(id)-\($0)", "fullName": "Học sinh \($0)", "rosterNumber": NSNull(), "absent": absent.contains($0)] as [String: Any] },
            ]
        }
        func payload(date: String = "2026-10-07", year: Bool = true) -> [String: Any] {
            [
                "date": date, "today": "2026-10-07", "canChooseDate": false,
                "schoolYear": year ? ["_id": "year", "name": "2026–2027", "startDate": "2026-08-01", "endDate": "2027-06-01"] as [String: Any] : NSNull(),
                "schoolDay": ["isSchoolDay": true, "kind": "school_day", "outsideYear": false],
                "grades": [
                    ["gradeLevel": 6, "classes": [klass("6A1", grade: 6, saved: true, absent: ["s2"]), klass("6A2", grade: 6, saved: false)]],
                    ["gradeLevel": 7, "classes": [[String: Any]]()],
                    ["gradeLevel": 8, "classes": [[String: Any]]()],
                    ["gradeLevel": 9, "classes": [[String: Any]]()],
                ],
            ]
        }

        // Decoding + grade tabs ("Lớp 6 · 1/2").
        let roster = try SupervisorAttendance.decodeRoster(payload())
        check(roster.schoolYear?.name == "2026–2027" && !roster.canChooseDate && roster.schoolDay.isSchoolDay, "Roster header fields")
        check(SupervisorAttendance.gradeTabs == [6, 7, 8, 9], "Lớp 6–9 tabs")
        check(SupervisorAttendance.classes(roster, grade: 6).map(\.id) == ["6A1", "6A2"], "Classes of grade in server order")
        check(SupervisorAttendance.gradeTabTitle(roster, grade: 6) == "Lớp 6 · 1/2", "Saved/total on grade tab")
        check(SupervisorAttendance.gradeTabTitle(roster, grade: 7) == "Lớp 7 · 0/0", "Empty grade tab")
        check(SupervisorAttendance.gradeTabTitle(nil, grade: 8) == "Lớp 8", "Tab before load")
        check(SupervisorAttendance.classes(roster, grade: 10).isEmpty, "Unknown grade is empty")
        let noYear = try SupervisorAttendance.decodeRoster(payload(year: false))
        check(noYear.schoolYear == nil, "Date outside every school year")

        // Status text: "Chưa điểm danh" / "Đã lưu HH:mm · N vắng" (Vietnam time).
        let saved = SupervisorAttendance.classes(roster, grade: 6)[0]
        check(SupervisorAttendance.classStatusText(nil) == "Chưa điểm danh", "Not marked")
        check(SupervisorAttendance.vietnamHm(savedAt) == "07:42", "Vietnam HH:mm")
        check(SupervisorAttendance.classStatusText(saved.saved) == "Đã lưu 07:42 · 1 vắng", "Saved status")
        check(SupervisorAttendance.headerSubtitle(roster, date: "2026-10-07") == "Thứ Tư, 07/10/2026 · Năm học 2026–2027", "Header date + school year")

        // Malformed payloads are rejected, never rendered.
        for key in ["date", "today", "canChooseDate", "schoolDay", "grades"] {
            var bad = payload(); bad.removeValue(forKey: key)
            rejects({ _ = try SupervisorAttendance.decodeRoster(bad) }, "Missing \(key)")
        }
        var badDate = payload(); badDate["date"] = "2026-13-01"
        rejects({ _ = try SupervisorAttendance.decodeRoster(badDate) }, "Invalid date")
        var badStudent = payload()
        badStudent["grades"] = [["gradeLevel": 6, "classes": [["classId": "x", "students": [["studentId": "", "absent": false]]]]]]
        rejects({ _ = try SupervisorAttendance.decodeRoster(badStudent) }, "Empty student id")
        var duplicate = payload()
        duplicate["grades"] = [["gradeLevel": 6, "classes": [["classId": "x", "students": [["studentId": "a", "absent": false], ["studentId": "a", "absent": true]]]]]]
        rejects({ _ = try SupervisorAttendance.decodeRoster(duplicate) }, "Duplicate student id")
        var badSaved = payload()
        badSaved["grades"] = [["gradeLevel": 6, "classes": [["classId": "x", "saved": ["savedAt": -1, "absentCount": 0], "students": [[String: Any]]()]]]]
        rejects({ _ = try SupervisorAttendance.decodeRoster(badSaved) }, "Negative savedAt")

        // Draft: everyone attends by default, Vắng toggles, dirty tracking, deterministic payload.
        var draft = AttendanceClassDraft(SupervisorAttendance.classes(roster, grade: 6)[1])
        check(draft.absentCount == 0 && draft.presentCount == 3 && !draft.isDirty, "Default attending, clean")
        draft.toggle("6A2-s3"); draft.toggle("6A2-s1")
        check(draft.isDirty && draft.absentCount == 2 && draft.summary == "2 vắng · 1 có mặt · chưa lưu", "Toggle marks absent + dirty")
        draft.toggle("not-enrolled")
        check(draft.absentCount == 2, "Unknown student ignored")
        let args = draft.saveArgs(date: "2026-10-07")
        check(args["classId"] as? String == "6A2" && args["date"] as? String == "2026-10-07" && args["absentStudentIds"] as? [String] == ["6A2-s1", "6A2-s3"], "saveClass args")
        draft.toggle("6A2-s1"); draft.toggle("6A2-s3")
        check(!draft.isDirty, "Toggling back is clean again")
        var existing = AttendanceClassDraft(saved)
        check(existing.isAbsent("6A1-s2") && !existing.isDirty, "Saved absences preloaded")
        existing.toggle("6A1-s2"); existing.markSaved()
        check(!existing.isDirty && existing.absentCount == 0 && existing.summary == "0 vắng · 3 có mặt", "markSaved resets baseline")
        check(SupervisorAttendance.saveButtonTitle(className: "6A2", absentCount: 2, busy: false) == "Lưu lớp 6A2 (2 vắng)", "Save label")
        check(SupervisorAttendance.saveButtonTitle(className: "6A2", absentCount: 2, busy: true) == "Đang lưu…", "Busy label")
        check(SupervisorAttendance.clampDate("2026-10-09", today: "2026-10-07") == "2026-10-07" && SupervisorAttendance.clampDate("2026-10-01", today: "2026-10-07") == "2026-10-01" && SupervisorAttendance.clampDate("bad", today: "2026-10-07") == "2026-10-07", "Never a future date")

        // Repository: exact endpoints/args, server-chosen today, ack validation, error wording.
        let fixture = Fixture(roster: payload())
        let repository = SupervisorAttendanceRepository(query: fixture.query, mutation: fixture.mutation)
        _ = try await repository.roster(date: nil)
        check(fixture.calls.last?.0 == "supervisorAttendance:roster" && fixture.calls.last?.1.isEmpty == true, "First load lets the server pick today")
        _ = try await repository.roster(date: "2026-10-07")
        check(fixture.calls.last?.1["date"] as? String == "2026-10-07", "Date passed through")
        do { _ = try await repository.roster(date: "2026-10-06"); check(false, "Mismatched date accepted") } catch { check(true, "Response for another date rejected") }
        var toSave = AttendanceClassDraft(SupervisorAttendance.classes(roster, grade: 6)[1]); toSave.toggle("6A2-s2")
        let result = try await repository.saveClass(date: "2026-10-07", draft: toSave)
        check(fixture.calls.last?.0 == "supervisorAttendance:saveClass" && fixture.calls.last?.1["absentStudentIds"] as? [String] == ["6A2-s2"], "saveClass endpoint + args")
        check(result.absentCount == 1 && result.presentCount == 2, "Save result decoded")
        check(SupervisorAttendance.saveSuccessMessage(className: "6A2", result: result) == "Đã lưu lớp 6A2: 1 vắng, 2 có mặt.", "Success wording mirrors web")
        fixture.malformedAck = true
        do { _ = try await repository.saveClass(date: "2026-10-07", draft: toSave); check(false, "Malformed ack") } catch { check((error as? ConvexException)?.code == "INVALID_MUTATION_ACK", "Malformed ack is not success") }
        fixture.failure = "Uncaught Error: ATTENDANCE_DATE_TODAY_ONLY"
        do { _ = try await repository.saveClass(date: "2026-10-06", draft: toSave); check(false, "Server rejection") } catch { check(error.localizedDescription == "Giám thị chỉ được điểm danh cho ngày hôm nay.", "Server code → Vietnamese message") }
        for (raw, message) in [
            ("SUPERVISOR_REQUIRED", "Chỉ Giám thị hoặc Admin/Mod mới được điểm danh."),
            ("ATTENDANCE_DATE_IN_FUTURE", "Không thể điểm danh cho ngày trong tương lai."),
            ("ATTENDANCE_DATE_OUTSIDE_YEAR", "Ngày điểm danh nằm ngoài thời gian của năm học."),
            ("ATTENDANCE_STUDENT_NOT_IN_CLASS", "Có học sinh không thuộc lớp này vào ngày điểm danh. Vui lòng tải lại rồi lưu lại."),
            ("ATTENDANCE_TOO_MANY_ABSENT", "Số học sinh vắng vượt quá giới hạn của một lớp."),
            ("CLASS_ARCHIVED", "Lớp đã lưu trữ. Không thể phân công, nhập danh sách hoặc điểm danh."),
            ("ATTENDANCE_CAMERA_IMPORT_RETIRED", "Nhập file điểm danh camera đã ngừng sử dụng. Giám thị điểm danh tại menu Điểm danh."),
            ("INVALID_DATE", "Ngày không hợp lệ."),
        ] {
            check(ConvexHttpClient.humanize("Uncaught Error: \(raw)\n    at handler") == message, "Message for \(raw)")
            check(!ConvexHttpClient.humanize(raw).contains("mật khẩu"), "\(raw) is not a login error")
        }
        print("PASS \(checks) Điểm danh offline checks (decode, tabs, status, draft, repository, error wording); no network/app launch")
    }
}

private final class Fixture: @unchecked Sendable {
    let roster: [String: Any]
    var calls: [(String, [String: Any])] = []
    var malformedAck = false
    var failure: String?
    init(roster: [String: Any]) { self.roster = roster }

    func query(_ path: String, _ args: [String: Any]) async throws -> [String: Any] {
        calls.append((path, args))
        guard path == "supervisorAttendance:roster" else { throw ConvexException(code: "UNEXPECTED_OFFLINE_QUERY") }
        var value = roster
        if let date = args["date"] as? String, date != "2026-10-06" { value["date"] = date }
        return value
    }

    func mutation(_ path: String, _ args: [String: Any]) async throws -> [String: Any] {
        calls.append((path, args))
        if let failure { throw ConvexException(code: ConvexHttpClient.extractCode(failure), message: ConvexHttpClient.humanize(failure)) }
        guard path == "supervisorAttendance:saveClass" else { throw ConvexException(code: "UNEXPECTED_OFFLINE_MUTATION") }
        if malformedAck { return ["classId": "other"] }
        let absent = (args["absentStudentIds"] as? [String] ?? []).count
        return ["classId": args["classId"] ?? "", "savedAt": 1791333720000.0, "presentCount": 3 - absent, "absentCount": absent, "changedCount": 3]
    }
}

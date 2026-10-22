import Foundation

@main struct HomeroomWriteChecks {
    @MainActor static func main() async throws {
        let context = DetailContext(yearId: "year", classId: "class", date: "2026-10-07", from: "2026-08-01", to: "2027-06-01")
        let target = AbsenceTarget(id: "day", studentId: "student", context: context)
        let single = try HomeroomWritePayload.disposition(target, next: "excused", reason: "", note: "Offline fixture reason")
        // Reason/note are optional since the Điểm danh redesign: the GVCN toggle sends only id + next disposition.
        let toggle = try HomeroomWritePayload.disposition(target, next: "unexcused")
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
        func rejected(_ operation: () throws -> Void) { do { try operation(); check(false, "Invalid offline input accepted") } catch { check(true, "Rejected") } }
        check(toggle.path == "studentAttendance:setDisposition" && Set(toggle.args.keys) == ["attendanceDayId", "nextDisposition"] && toggle.args["nextDisposition"] as? String == "unexcused", "Reasonless unexcused toggle")
        check(try HomeroomWritePayload.disposition(target, next: "excused").args["nextDisposition"] as? String == "excused", "Reasonless excused toggle")
        check(try HomeroomWritePayload.disposition(target, next: "unexcused", reason: " leave ", note: " kept ").args["reasonCode"] as? String == "leave", "Existing reason/note passed back trimmed")
        check(HomeroomPresentation.nextDisposition(unexcused: true) == "unexcused" && HomeroomPresentation.nextDisposition(unexcused: false) == "excused", "Toggle mapping")
        // No pending/none/exempt from the toggle, no batch, notes ≤500, valid context.
        for next in ["none", "exempt", "present", "pending"] { rejected { _ = try HomeroomWritePayload.disposition(target, next: next, reason: "fixture") } }
        rejected { _ = try HomeroomWritePayload.disposition(target, next: "excused", note: String(repeating: "x", count: 501)) }
        rejected { _ = try HomeroomWritePayload.disposition(AbsenceTarget(id: "", studentId: "student", context: context), next: "excused") }
        rejected { _ = try HomeroomWritePayload.disposition(AbsenceTarget(id: "day", studentId: "student", context: DetailContext(yearId: "year", classId: "class", date: "bad", from: "2026-08-01", to: "2027-06-01")), next: "excused") }
        rejected { try HomeroomWritePayload.validate(HomeroomWrite(path: "studentAttendance:setDispositionMany", args: ["attendanceDayIds": ["day"], "nextDisposition": "excused"], context: context, targets: [target])) }
        for phone in ["12345", "123456789012345678901", "abc123"] { rejected { _ = try HomeroomWritePayload.studentPhone(context, studentId: "student", value: phone) } }
        let phone = try HomeroomWritePayload.studentPhone(context, studentId: "student", value: "0123456")
        let clearedPhone = try HomeroomWritePayload.studentPhone(context, studentId: "student", value: " ")
        check(clearedPhone.args["studentPhone"] as? String == "", "Clear phone")
        let add = try HomeroomWritePayload.guardian(context, studentId: "student", id: nil, relationship: "mother", name: "  Nguyễn  Thị  A ", phone: "", primary: false, notes: " fixture ")
        let edit = try HomeroomWritePayload.guardian(context, studentId: "student", id: "g0", relationship: "mother", name: "Name", phone: "+84 (123)", primary: true, notes: "")
        let remove = HomeroomWritePayload.remove(context, studentId: "student", id: "g0")
        check(add.args["fullName"] as? String == "Nguyễn Thị A" && add.args["notes"] as? String == "fixture", "Normalize")
        check(try HomeroomWritePayload.guardian(context, studentId: "student", id: nil, relationship: "other", name: "\u{FEFF}Name\u{00A0}\u{2003}A\u{FEFF}", phone: "", primary: false, notes: "").args["fullName"] as? String == "Name A", "Backend Unicode whitespace normalization")
        check(try HomeroomWritePayload.phone("\u{FEFF}123\u{00A0}456\u{FEFF}") == "123\u{00A0}456", "Backend whitespace phone regex")
        check(Set(remove.args.keys) == ["studentId", "guardianId"], "Remove exact payload")
        for (name, notes, relationship) in [("", "", "mother"), (String(repeating: "x", count: 121), "", "mother"), ("Name", String(repeating: "x", count: 301), "mother"), ("Name", "", "invalid")] { rejected { _ = try HomeroomWritePayload.guardian(context, studentId: "student", id: nil, relationship: relationship, name: name, phone: "", primary: false, notes: notes) } }
        for role in ["supervisor", "view_all", "access-revoked"] {
            let fake = OfflineWriteFixture(context); fake.denied = true
            let repo = fake.repository()
            for write in [single, phone] {
                do { _ = try await repo.submit(write, isCurrent: { true }); check(false, "Denied \(role)") } catch { check(true, "Denied \(role)") }
            }
            check(fake.writes.isEmpty, "No denied mutation \(role)")
        }
        let revoked = OfflineWriteFixture(context)
        check(try HomeroomDetailDecoder.profile(revoked.profile()).permissions.canEditContacts, "Initially authorized profile read")
        check(try HomeroomDetailDecoder.daily(await revoked.query("studentAttendance:listDailyClass", [:])).canCorrect, "Initially authorized attendance read")
        revoked.denied = true
        for write in [single, phone] {
            do { _ = try await revoked.repository().submit(write, isCurrent: { true }); check(false, "Access revoked between read and submit") } catch { check(true, "Fresh revoked read blocks submit") }
        }
        check(revoked.writes.isEmpty, "No write after permission revocation")
        for fault in ["present", "late", "unknown", "archived", "date", "class", "year", "student", "missing"] {
            let fake = OfflineWriteFixture(context); fake.fault = fault
            do { _ = try await fake.repository().submit(single, isCurrent: { true }); check(false, "Invalid target \(fault)") } catch { check(true, "Invalid target \(fault)") }
            check(fake.writes.isEmpty, "No mutation wrong scope/raw/archived")
        }
        let redaction = OfflineWriteFixture(context)
        var redacted = redaction.profile()
        redacted["showContacts"] = false; redacted["guardians"] = [["phone": ["malformed": true]]]
        var student = redacted["student"] as! [String: Any]; student["studentPhone"] = ["malformed": true]; redacted["student"] = student
        let profile = try HomeroomDetailDecoder.profile(redacted)
        check(profile.studentPhone == nil && profile.guardians.isEmpty, "Redacted values never decoded")
        redacted["showContacts"] = true
        rejected { _ = try HomeroomDetailDecoder.profile(redacted) }
        check(try HomeroomDetailDecoder.profile(redaction.profile()).studentPhone == "0123456", "Backend showContacts true despite includeSensitiveContacts:false")
        let limit = OfflineWriteFixture(context); limit.guardianCount = 6
        do { _ = try await limit.repository().submit(add, isCurrent: { true }); check(false, "Seventh guardian") } catch { check(true, "Limit") }
        check(limit.writes.isEmpty, "No seventh mutation")
        check(try await limit.repository().submit(edit, isCurrent: { true }).refreshFailed == false, "Edit six allowed")
        limit.guardianCount = 7
        do { _ = try await limit.repository().submit(edit, isCurrent: { true }); check(false, "Malformed seven contacts") } catch { check(true, "Malformed seven") }
        check(limit.writes.count == 1, "No seven mutation")
        for write in [single, toggle, phone, add, remove] {
            let fake = OfflineWriteFixture(context); fake.guardianCount = 1
            var acknowledged = false
            let receipt = try await fake.repository().submit(write, isCurrent: { true }, onAcknowledged: { acknowledged = true })
            check(!receipt.refreshFailed && acknowledged && fake.writes.count == 1, "Acknowledged offline mutation + refresh")
            check(fake.writes[0].0 == write.path && NSDictionary(dictionary: fake.writes[0].1).isEqual(to: write.args), "Exact mutation path/payload")
            check(!fake.reads.contains("homeroomReports:pendingAbsences") && !fake.reads.contains("homeroomReports:overview"), "Retired pending inbox never read")
            check(fake.reads.filter { $0 == "studentAttendance:listDailyClass" }.count >= (write.targets.isEmpty ? 1 : 2), "Class day re-read after write")
            check(fake.reads.contains("studentAttendance:getStudentHistory") == write.targets.isEmpty, "Contacts re-read the student; toggles only the class")
        }
        let post = OfflineWriteFixture(context); post.postReadFailure = true
        let postReceipt = try await post.repository().submit(single, isCurrent: { true })
        check(postReceipt.refreshFailed && postReceipt.status.contains("xác nhận") && postReceipt.status.contains("không gửi lại") && post.writes.count == 1, "Read failure not write failure")
        for write in [single, toggle, phone, add] {
            let fake = OfflineWriteFixture(context); fake.malformedAck = true
            let before = NSDictionary(dictionary: write.args)
            do { _ = try await fake.repository().submit(write, isCurrent: { true }); check(false, "Malformed acknowledgment") }
            catch { check((error as? ConvexException)?.code == "WRITE_UNCERTAIN", "Uncertain, never fake success") }
            check(before.isEqual(to: write.args) && fake.writes.count == 1, "Preserve edits without retry")
        }
        for path in ["students:updateContacts", "students:removeGuardian"] {
            try ConvexHttpClient.validateHomeroomAcknowledgment(path, envelope: ["status": "success", "value": NSNull()], statusCode: 200)
            for bad: [String: Any] in [["status": "success"], ["status": "success", "value": [:]], ["status": "success", "value": false]] { rejected { try ConvexHttpClient.validateHomeroomAcknowledgment(path, envelope: bad, statusCode: 200) } }
            rejected { try ConvexHttpClient.validateHomeroomAcknowledgment(path, envelope: ["status": "success", "value": NSNull()], statusCode: 500) }
        }
        let duplicate = OfflineWriteFixture(context)
        var release: CheckedContinuation<Void, Never>?
        let repo = HomeroomWriteRepository(query: duplicate.query, mutation: { path, args in
            await withCheckedContinuation { release = $0 }
            return try await duplicate.mutation(path, args)
        })
        let first = Task { try await repo.submit(single, isCurrent: { true }) }
        while release == nil { await Task.yield() }
        do { _ = try await repo.submit(single, isCurrent: { true }); check(false, "Duplicate submit") } catch { check((error as? ConvexException)?.code == "WRITE_BUSY", "Duplicate blocked") }
        release?.resume(); _ = try await first.value
        check(duplicate.writes.count == 1, "Exactly one mutation")
        var current = true
        let stale = OfflineWriteFixture(context)
        let staleRepo = HomeroomWriteRepository(query: { path, args in let result = try await stale.query(path, args); if path == "studentAttendance:listDailyClass" { current = false }; return result }, mutation: stale.mutation)
        do { _ = try await staleRepo.submit(single, isCurrent: { current }); check(false, "Late context") } catch { check(true, "Late context") }
        check(stale.writes.isEmpty, "No stale-context write")
        var waiting: CheckedContinuation<Void, Never>?
        let cancel = OfflineWriteFixture(context)
        let cancelRepo = HomeroomWriteRepository(query: { path, args in await withCheckedContinuation { waiting = $0 }; return try await cancel.query(path, args) }, mutation: cancel.mutation)
        let task = Task { try await cancelRepo.submit(single, isCurrent: { true }) }
        while waiting == nil { await Task.yield() }; task.cancel(); waiting?.resume()
        do { _ = try await task.value; check(false, "Cancellation") } catch { check(true, "Cancellation") }
        check(cancel.writes.isEmpty, "Cancelled request never writes")
        let validationFake = OfflineWriteFixture(context)
        let validation = HomeroomWriteRepository(query: validationFake.query, mutation: { _, _ in throw ConvexException(code: "INVALID_DISPOSITION_NOTE") })
        let before = NSDictionary(dictionary: single.args)
        do { _ = try await validation.submit(single, isCurrent: { true }); check(false, "Validation failure") } catch { check((error as? ConvexException)?.code == "INVALID_DISPOSITION_NOTE", "Definite failure preserves editability") }
        check(before.isEqual(to: single.args), "Edits preserved")
        check(ConvexHttpClient.extractCode("Uncaught Error: INVALID_DISPOSITION_NOTE at offline fixture") == "INVALID_DISPOSITION_NOTE", "Actual client preserves known server validation code")
        check(!ConvexHttpClient.humanize("INVALID_PHONE").contains("mật khẩu"), "Contact errors do not claim login failure")
        let deniedMutation = HomeroomWriteRepository(query: validationFake.query, mutation: { _, _ in throw ConvexException(code: "CONTACT_EDIT_FORBIDDEN") })
        do { _ = try await deniedMutation.submit(single, isCurrent: { true }); check(false, "Write revoked") } catch { check((error as? ConvexException)?.code == "WRITE_DENIED", "Denied clears eligibility") }
        let wrongAck = OfflineWriteFixture(context).repository()
        for bad: [String: Any] in [[:], ["updated": 1], ["attendanceDayId": "day", "effectiveStatus": "absent_pending", "unchanged": false], ["attendanceDayId": "other", "effectiveStatus": "absent_excused", "unchanged": false], ["attendanceDayId": "day", "effectiveStatus": "absent_excused", "unchanged": "no"]] { rejected { try wrongAck.validateAck(single, bad) } }
        var tampered = toggle.args; tampered["attendanceDayId"] = "outside-context"
        do { _ = try await OfflineWriteFixture(context).repository().submit(HomeroomWrite(path: toggle.path, args: tampered, context: toggle.context, targets: toggle.targets), isCurrent: { true }); check(false, "Tampered payload") } catch { check(true, "Context payload rejected") }
        print("PASS \(checks) deterministic Swift L3 assertions; injected offline fixtures only, no network/app launch")
    }
}

@MainActor private final class OfflineWriteFixture {
    let context: DetailContext
    var denied = false; var fault = ""; var guardianCount = 0; var malformedAck = false; var postReadFailure = false
    var expandedDays = 0
    var writes: [(String, [String: Any])] = []
    var reads: [String] = []
    init(_ context: DetailContext) { self.context = context }
    func repository() -> HomeroomWriteRepository { HomeroomWriteRepository(query: query, mutation: mutation) }
    func profile() -> [String: Any] {
        ["student": ["_id": "student", "studentCode": "S01", "fullName": "Offline fixture student", "status": "active", "studentPhone": "0123456"], "enrollments": [["_id": "e", "classId": "class", "classCode": "6A", "className": "Class", "startDate": "2026-08-01", "status": "active", "current": false]], "guardians": (0..<guardianCount).map { ["_id": "g\($0)", "relationship": "mother", "fullName": "Guardian fixture", "isPrimaryContact": $0 == 0] as [String: Any] }, "showContacts": true, "permissions": ["canManage": false, "canEditContacts": !denied]]
    }
    func query(_ path: String, _ args: [String: Any]) async throws -> [String: Any] {
        reads.append(path)
        if postReadFailure && !writes.isEmpty { throw ConvexException(code: "OFFLINE_READBACK_ERROR") }
        switch path {
        case "homeroomClasses:getScoped": return ["class": ["_id": fault == "class" ? "wrong" : "class", "schoolYearId": fault == "year" ? "wrong" : "year", "code": "6A", "name": "Offline fixture class", "status": fault == "archived" ? "archived" : "active"], "schoolYear": NSNull(), "assignments": [], "currentTeacherName": "", "rosterCount": 1, "permissions": ["canManage": false, "canImportAttendance": false, "canCorrect": !denied, "canEditContacts": !denied]]
        case "students:listByClass": return ["rows": [], "showContacts": false]
        case "studentAttendance:listDailyClass":
            let rows: [[String: Any]] = (0..<max(expandedDays, 1)).map { number in ["enrollment": ["_id": "e"], "student": ["_id": fault == "student" ? "other" : "student", "studentCode": "S01", "fullName": "Offline fixture"], "day": ["_id": expandedDays > 0 ? "day\(number + 1)" : (fault == "missing" ? "wrong" : "day"), "rawObservation": ["present", "late", "unknown"].contains(fault) ? fault : "absent", "disposition": "pending", "effectiveStatus": "absent_pending"]] }
            return ["date": fault == "date" ? "2026-10-06" : context.date, "rows": rows, "published": true, "archived": false, "canCorrect": !denied, "schoolDay": ["isSchoolDay": true, "kind": "school_day", "outsideYear": false]]
        case "students:getScoped": return profile()
        case "studentAttendance:getStudentHistory": return ["days": [], "corrections": []]
        case "homeroomReports:overview": return ["date": context.date, "today": context.date, "mode": "teacher", "schoolYear": ["_id": "year", "name": "Offline fixture year", "startDate": "2026-08-01", "endDate": "2027-06-01", "active": true], "schoolDay": ["isSchoolDay": true, "kind": "school_day", "outsideYear": false], "classes": [], "studentCount": 0, "summary": ["counts": ["present": 0, "late": 0, "absent_excused": 0, "absent_unexcused": 0, "absent_pending": 0, "no_data": 0, "exempt": 0], "attendanceRate": 0, "ratedRows": 0, "totalRows": 0], "missingUpload": ["shouldAlert": false, "cutoffTime": "08:00", "missingClassCodes": []], "pendingTotal": 0]
        default: throw ConvexException(code: "UNEXPECTED_OFFLINE_QUERY")
        }
    }
    func mutation(_ path: String, _ args: [String: Any]) async throws -> [String: Any] {
        writes.append((path, args))
        if malformedAck { return ["unexpected": true] }
        switch path {
        case "studentAttendance:setDisposition": return ["attendanceDayId": args["attendanceDayId"]!, "effectiveStatus": args["nextDisposition"] as? String == "unexcused" ? "absent_unexcused" : "absent_excused", "unchanged": false]
        case "students:upsertGuardian": return ["value": args["guardianId"] ?? "guardian-fixture-id"]
        default: return [:]
        }
    }
}

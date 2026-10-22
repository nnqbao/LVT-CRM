import Foundation

/// Điểm danh menu (Giám thị or admin/mod): models, decoding, local editing state and the repository for
/// `supervisorAttendance.roster` / `supervisorAttendance.saveClass`. Foundation only, so it is checkable offline.
/// The backend re-checks the actor and the date on every call; nothing here is enforcement.

struct AttendanceSaved: Equatable, Sendable {
    let savedAt: Double
    let savedByName: String
    let source: String
    let presentCount: Int
    let absentCount: Int
}

struct AttendanceStudent: Equatable, Sendable, Identifiable {
    let id: String
    let fullName: String
    let rosterNumber: Int?
    let absent: Bool
}

struct AttendanceClass: Equatable, Sendable, Identifiable {
    let id: String
    let code: String
    let name: String
    let gradeLevel: Int
    let saved: AttendanceSaved?
    let students: [AttendanceStudent]

    var displayName: String { name.isEmpty ? code : name }
}

struct AttendanceGrade: Equatable, Sendable {
    let gradeLevel: Int
    let classes: [AttendanceClass]
}

struct AttendanceRoster: Equatable, Sendable {
    let date: String
    let today: String
    let canChooseDate: Bool
    let schoolYear: SchoolYear?
    let schoolDay: HomeroomSchoolDay
    let grades: [AttendanceGrade]
}

struct AttendanceSaveResult: Equatable, Sendable {
    let classId: String
    let savedAt: Double
    let presentCount: Int
    let absentCount: Int
}

enum SupervisorAttendance {
    /// Web `GRADE_TABS`: Lớp 6–9 tabs always exist.
    static let gradeTabs = [6, 7, 8, 9]
    static let unsavedPrompt = "Lớp đang mở có thay đổi chưa lưu. Bỏ các thay đổi này?"
    static let excelNote = "Nhập bằng Excel (file mẫu 3 cột): dùng bản web."

    static func decodeRoster(_ value: [String: Any]) throws -> AttendanceRoster {
        guard let date = value["date"] as? String, VietnamDate.date(from: date) != nil,
              let today = value["today"] as? String, VietnamDate.date(from: today) != nil,
              let canChooseDate = value["canChooseDate"] as? Bool,
              let schoolDay = value["schoolDay"] as? [String: Any],
              let grades = value["grades"] as? [[String: Any]] else { throw invalid() }
        var year: SchoolYear?
        if let raw = value["schoolYear"] as? [String: Any] {
            guard let id = raw["_id"] as? String, !id.isEmpty else { throw invalid() }
            year = SchoolYear(id: id, name: raw["name"] as? String ?? "", startDate: raw["startDate"] as? String ?? "", endDate: raw["endDate"] as? String ?? "", active: true)
        } else if !(value["schoolYear"] is NSNull) {
            throw invalid()
        }
        return AttendanceRoster(
            date: date,
            today: today,
            canChooseDate: canChooseDate,
            schoolYear: year,
            schoolDay: HomeroomSchoolDay(
                isSchoolDay: schoolDay["isSchoolDay"] as? Bool ?? false,
                kind: schoolDay["kind"] as? String ?? "",
                note: schoolDay["note"] as? String ?? "",
                outsideYear: schoolDay["outsideYear"] as? Bool ?? false
            ),
            grades: try grades.map(decodeGrade)
        )
    }

    private static func decodeGrade(_ row: [String: Any]) throws -> AttendanceGrade {
        guard let grade = (row["gradeLevel"] as? NSNumber)?.intValue, let classes = row["classes"] as? [[String: Any]] else { throw invalid() }
        return AttendanceGrade(gradeLevel: grade, classes: try classes.map(decodeClass))
    }

    private static func decodeClass(_ row: [String: Any]) throws -> AttendanceClass {
        guard let id = row["classId"] as? String, !id.isEmpty,
              let students = row["students"] as? [[String: Any]] else { throw invalid() }
        var saved: AttendanceSaved?
        if let raw = row["saved"] as? [String: Any] {
            guard let savedAt = (raw["savedAt"] as? NSNumber)?.doubleValue, savedAt.isFinite, savedAt >= 0,
                  let absent = (raw["absentCount"] as? NSNumber)?.intValue, absent >= 0 else { throw invalid() }
            saved = AttendanceSaved(
                savedAt: savedAt,
                savedByName: raw["savedByName"] as? String ?? "",
                source: raw["source"] as? String ?? "",
                presentCount: (raw["presentCount"] as? NSNumber)?.intValue ?? 0,
                absentCount: absent
            )
        } else if row["saved"] != nil, !(row["saved"] is NSNull) {
            throw invalid()
        }
        let decodedStudents: [AttendanceStudent] = try students.map { student in
            guard let studentId = student["studentId"] as? String, !studentId.isEmpty,
                  let absent = student["absent"] as? Bool else { throw invalid() }
            return AttendanceStudent(
                id: studentId,
                fullName: student["fullName"] as? String ?? "",
                rosterNumber: (student["rosterNumber"] as? NSNumber)?.intValue,
                absent: absent
            )
        }
        guard Set(decodedStudents.map(\.id)).count == decodedStudents.count else { throw invalid() }
        return AttendanceClass(
            id: id,
            code: row["code"] as? String ?? "",
            name: row["name"] as? String ?? "",
            gradeLevel: (row["gradeLevel"] as? NSNumber)?.intValue ?? 0,
            saved: saved,
            students: decodedStudents
        )
    }

    static func decodeSaveResult(_ value: [String: Any], classId: String) throws -> AttendanceSaveResult {
        guard value["classId"] as? String == classId,
              let savedAt = (value["savedAt"] as? NSNumber)?.doubleValue,
              let present = (value["presentCount"] as? NSNumber)?.intValue, present >= 0,
              let absent = (value["absentCount"] as? NSNumber)?.intValue, absent >= 0 else {
            throw ConvexException(code: "INVALID_MUTATION_ACK", message: "Chưa xác nhận được kết quả lưu. Tải lại để kiểm tra trước khi lưu lại.")
        }
        return AttendanceSaveResult(classId: classId, savedAt: savedAt, presentCount: present, absentCount: absent)
    }

    static func classes(_ roster: AttendanceRoster?, grade: Int) -> [AttendanceClass] {
        roster?.grades.first { $0.gradeLevel == grade }?.classes ?? []
    }

    /// "Lớp 6 · 2/5": saved classes / classes of the grade.
    static func gradeTabTitle(_ roster: AttendanceRoster?, grade: Int) -> String {
        let list = classes(roster, grade: grade)
        guard roster != nil else { return "Lớp \(grade)" }
        return "Lớp \(grade) · \(list.filter { $0.saved != nil }.count)/\(list.count)"
    }

    /// HH:mm in Asia/Ho_Chi_Minh.
    static func vietnamHm(_ milliseconds: Double) -> String {
        guard milliseconds > 0 else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = VietnamDate.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: milliseconds / 1000))
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Web `classStatusText`.
    static func classStatusText(_ saved: AttendanceSaved?) -> String {
        guard let saved else { return "Chưa điểm danh" }
        return "Đã lưu \(vietnamHm(saved.savedAt)) · \(saved.absentCount) vắng"
    }

    static func saveButtonTitle(className: String, absentCount: Int, busy: Bool) -> String {
        busy ? "Đang lưu…" : "Lưu lớp \(className) (\(absentCount) vắng)"
    }

    static func saveSuccessMessage(className: String, result: AttendanceSaveResult) -> String {
        "Đã lưu lớp \(className): \(result.absentCount) vắng, \(result.presentCount) có mặt."
    }

    /// "Thứ Năm, 22/10/2026 · Năm học 2026–2027".
    static func headerSubtitle(_ roster: AttendanceRoster?, date: String) -> String {
        let day = "\(HomeroomPresentation.dayTitle(date).components(separatedBy: ",").first ?? ""), \(VietnamDate.display(date))"
        guard let year = roster?.schoolYear else { return day }
        return "\(day) · Năm học \(year.name)"
    }

    /// Admin/mod may pick a past date (never future); Giám thị is fixed to today.
    static func clampDate(_ value: String, today: String) -> String {
        guard VietnamDate.date(from: value) != nil else { return today }
        return value > today ? today : value
    }

    private static func invalid() -> ConvexException {
        ConvexException(code: "INVALID_RESPONSE", message: "Phản hồi điểm danh không hợp lệ.")
    }
}

/// Local edits for the one open class: default attending, "Vắng" toggles, dirty tracking (web ClassEditor).
struct AttendanceClassDraft: Equatable {
    let classId: String
    private(set) var initialAbsent: Set<String>
    private(set) var absent: Set<String>
    private let enrolled: Set<String>
    let total: Int

    init(_ klass: AttendanceClass) {
        classId = klass.id
        initialAbsent = Set(klass.students.filter(\.absent).map(\.id))
        absent = initialAbsent
        enrolled = Set(klass.students.map(\.id))
        total = klass.students.count
    }

    var isDirty: Bool { absent != initialAbsent }

    /// After an acknowledged save the local selection is the new baseline.
    mutating func markSaved() { initialAbsent = absent }
    var absentCount: Int { absent.count }
    var presentCount: Int { total - absent.count }

    func isAbsent(_ studentId: String) -> Bool { absent.contains(studentId) }

    /// Only students enrolled in the class can be toggled.
    mutating func toggle(_ studentId: String) {
        guard enrolled.contains(studentId) else { return }
        if absent.contains(studentId) { absent.remove(studentId) } else { absent.insert(studentId) }
    }

    /// `supervisorAttendance.saveClass` args; ids sorted so the payload is deterministic.
    func saveArgs(date: String) -> [String: Any] {
        ["date": date, "classId": classId, "absentStudentIds": absent.sorted()]
    }

    /// "3 vắng · 38 có mặt · chưa lưu".
    var summary: String {
        "\(absentCount) vắng · \(presentCount) có mặt" + (isDirty ? " · chưa lưu" : "")
    }
}

final class SupervisorAttendanceRepository: Sendable {
    typealias RPC = @Sendable (String, [String: Any]) async throws -> [String: Any]
    private let query: RPC
    private let mutation: RPC

    init(query: @escaping RPC, mutation: @escaping RPC) {
        self.query = query
        self.mutation = mutation
    }

    convenience init(convex: ConvexHttpClient) {
        self.init(
            query: { path, args in try await convex.query(path, args: args) },
            mutation: { path, args in try await convex.mutation(path, args: args) }
        )
    }

    /// Omitting the date asks the server for its Vietnam "today" (Giám thị can only read today).
    func roster(date: String?) async throws -> AttendanceRoster {
        var args: [String: Any] = [:]
        if let date { args["date"] = date }
        let roster = try SupervisorAttendance.decodeRoster(await query("supervisorAttendance:roster", args))
        if let date, roster.date != date {
            throw ConvexException(code: "INVALID_RESPONSE", message: "Phản hồi không khớp ngày đã chọn.")
        }
        return roster
    }

    func saveClass(date: String, draft: AttendanceClassDraft) async throws -> AttendanceSaveResult {
        guard VietnamDate.date(from: date) != nil, !draft.classId.isEmpty else { throw ConvexException(code: "INVALID_DATE") }
        return try SupervisorAttendance.decodeSaveResult(
            await mutation("supervisorAttendance:saveClass", draft.saveArgs(date: date)),
            classId: draft.classId
        )
    }
}

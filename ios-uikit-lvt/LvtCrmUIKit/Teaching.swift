import Foundation

// Lớp học (teaching): Tổng quan, Lớp giảng dạy + Sổ đầu bài, Lịch dạy, Học bạ.
// Pure Foundation: models, decoding, timetable expansion (mirror of src/lib/teachingSchedule.js), score parsing
// and formatting. Tests/TeachingChecks.swift exercises everything here offline. The server re-checks every call.

struct TeachingYear: Equatable, Sendable {
    let id: String
    let name: String
    let startDate: String
    let endDate: String
    let semester2StartDate: String
    let locked: Bool
}

struct TimetableSlot: Equatable, Sendable {
    let id: String
    let classId: String
    /// 1 = Thứ 2 … 5 = Thứ 6.
    let weekday: Int
    /// "morning" | "afternoon".
    let session: String
    let period: Int
    let teacherId: String
    let subjectId: String
    let effectiveFrom: String
    let effectiveTo: String?
}

struct TeachingClass: Equatable, Sendable {
    let id: String
    let name: String
    let gradeLevel: Int
    let status: String
}

struct Lesson: Equatable, Hashable, Sendable {
    let date: String
    let weekday: Int
    let session: String
    let period: Int
    let classId: String
    let teacherId: String
    let subjectId: String

    var cellKey: String { "\(session)-\(period)" }
}

struct LessonLogRecord: Equatable, Sendable {
    let id: String
    let classId: String
    let date: String
    let session: String
    let period: Int
    let rating: Int
    let comment: String
    let updatedAt: Double?
}

struct MyTeaching: Equatable, Sendable {
    let year: TeachingYear
    let today: String
    let holidays: Set<String>
    let slots: [TimetableSlot]
    let classes: [TeachingClass]
    let todayLogs: [LessonLogRecord]

    func className(_ id: String) -> String { classes.first { $0.id == id }?.name ?? "Lớp" }
}

struct CatalogSubject: Equatable, Sendable {
    let id: String
    let name: String
    let active: Bool
}

struct CatalogTestType: Equatable, Sendable {
    let id: String
    let name: String
    let coefficient: Int
}

struct TeachingCatalog: Equatable, Sendable {
    let subjects: [CatalogSubject]
    let testTypes: [CatalogTestType]

    func subjectName(_ id: String) -> String { subjects.first { $0.id == id }?.name ?? "Môn học" }
}

struct TeacherSchedule: Equatable, Sendable {
    let year: TeachingYear
    let teacherName: String
    let holidays: Set<String>
    let slots: [TimetableSlot]
    let classes: [TeachingClass]

    func className(_ id: String) -> String { classes.first { $0.id == id }?.name ?? "Lớp" }
}

struct ClassLessonLog: Equatable, Sendable {
    let id: String
    let date: String
    let session: String
    let period: Int
    let teacherName: String
    let subjectName: String
    let rating: Int
    let comment: String
    let updatedAt: Double
}

struct GradebookClassRow: Equatable, Sendable {
    let id: String
    let name: String
    let gradeLevel: Int
    let rosterCount: Int
    let isHomeroom: Bool
    let subjectIds: [String]
}

struct GradebookStudent: Equatable, Sendable {
    let id: String
    let fullName: String
    let studentCode: String
    let dateOfBirth: String
    let rosterNumber: Int?
}

struct GradebookClassStudents: Equatable, Sendable {
    let classId: String
    let className: String
    let gradeLevel: Int
    let yearName: String
    let students: [GradebookStudent]
}

struct GradeRecordYear: Equatable, Sendable {
    let id: String
    let name: String
    let semester2StartDate: String
    let locked: Bool
    let classId: String
    let className: String
    let gradeLevel: Int
}

struct GradeAverages: Equatable, Sendable {
    let semester1: Double?
    let semester2: Double?
    let year: Double?
}

struct GradeEntry: Equatable, Sendable {
    let id: String
    let subjectId: String
    let semester: Int
    let testTypeId: String
    let testTypeName: String
    let coefficient: Int
    let score: Double
    let createdAt: Double
    let enteredByName: String
    let canEdit: Bool
}

struct StudentRecord: Equatable, Sendable {
    let studentId: String
    let fullName: String
    let studentCode: String
    let dateOfBirth: String
    let years: [GradeRecordYear]
    let yearSummaries: [String: GradeAverages]
    let selectedYearId: String
    let selectedClassId: String
    let fullView: Bool
    let subjects: [CatalogSubject]
    let testTypes: [CatalogTestType]
    let subjectIds: [String]
    let writableSubjectIds: [String]
    let subjectSummaries: [String: GradeAverages]
    let summary: GradeAverages
    let entries: [GradeEntry]

    var selectedYear: GradeRecordYear? { years.first { $0.id == selectedYearId } }
    var canAddScore: Bool { !writableSubjectIds.isEmpty && !testTypes.isEmpty && !selectedClassId.isEmpty }
    func subjectName(_ id: String) -> String { subjects.first { $0.id == id }?.name ?? "Môn học" }
    func entries(subjectId: String, semester: Int) -> [GradeEntry] {
        entries.filter { $0.subjectId == subjectId && $0.semester == semester }
    }
}

/// Học sinh vắng hôm nay (homeroomReports:overview), only the fields Tổng quan needs.
struct TeachingAbsenceOverview: Equatable, Sendable {
    struct ClassRow: Equatable, Sendable {
        let id: String
        let name: String
        let rosterCount: Int
        let saved: Bool
        let excused: Int
        let unexcused: Int
        let absent: Int
    }

    let date: String
    let schoolWide: Bool
    let classes: [ClassRow]
    let absent: Int
    let excused: Int
    let unexcused: Int
}

// MARK: - Timetable (mirror of src/lib/teachingSchedule.js)

enum TeachingSchedule {
    static let weekdays = [1, 2, 3, 4, 5]
    static let sessions = ["morning", "afternoon"]
    static let periods = [1, 2, 3, 4, 5]
    static let weekdayLabels: [Int: String] = [1: "Thứ 2", 2: "Thứ 3", 3: "Thứ 4", 4: "Thứ 5", 5: "Thứ 6", 6: "Thứ 7", 7: "Chủ nhật"]
    static let periodStartTimes: [String: [String]] = [
        "morning": ["07:00", "07:50", "08:50", "09:40", "10:30"],
        "afternoon": ["13:30", "14:20", "15:20", "16:10", "17:00"],
    ]
    static let lookAheadDays = 35

    static func sessionLabel(_ session: String) -> String { session == "afternoon" ? "Chiều" : "Sáng" }

    /// "Tiết 3 sáng", "Tiết 1 chiều".
    static func periodLabel(session: String, period: Int) -> String {
        "Tiết \(period) \(sessionLabel(session).lowercased())"
    }

    static func weekdayLabel(_ ymd: String) -> String { weekdayLabels[isoWeekday(ymd)] ?? "" }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func components(_ ymd: String) -> (Int, Int, Int)? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    private static func date(_ ymd: String) -> Date? {
        guard let (y, m, d) = components(ymd) else { return nil }
        return utc.date(from: DateComponents(year: y, month: m, day: d))
    }

    private static func ymd(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func addDays(_ ymd: String, _ days: Int) -> String {
        guard let start = date(ymd), let next = utc.date(byAdding: .day, value: days, to: start) else { return ymd }
        return self.ymd(next)
    }

    /// 1 = Monday … 7 = Sunday.
    static func isoWeekday(_ ymd: String) -> Int {
        guard let value = date(ymd) else { return 0 }
        let weekday = utc.component(.weekday, from: value) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    static func weekStart(_ ymd: String) -> String { addDays(ymd, 1 - isoWeekday(ymd)) }
    static func monthStart(_ ymd: String) -> String { String(ymd.prefix(7)) + "-01" }

    static func monthEnd(_ ymd: String) -> String {
        guard let (y, m, _) = components(ymd),
              let first = utc.date(from: DateComponents(year: y, month: m, day: 1)),
              let range = utc.range(of: .day, in: .month, for: first) else { return ymd }
        return String(format: "%04d-%02d-%02d", y, m, range.count)
    }

    static func addMonths(_ ymd: String, _ months: Int) -> String {
        guard let (y, m, _) = components(ymd),
              let first = utc.date(from: DateComponents(year: y, month: m, day: 1)),
              let next = utc.date(byAdding: .month, value: months, to: first) else { return ymd }
        return self.ymd(next)
    }

    static func slotCovers(_ slot: TimetableSlot, date: String) -> Bool {
        slot.effectiveFrom <= date && (slot.effectiveTo.map { date <= $0 } ?? true)
    }

    static func isTimetableDay(_ date: String, year: TeachingYear, holidays: Set<String>) -> Bool {
        if date < year.startDate || date > year.endDate { return false }
        if isoWeekday(date) > 5 { return false }
        return !holidays.contains(date)
    }

    static func lessonStartTime(session: String, period: Int) -> String {
        let times = periodStartTimes[session] ?? periodStartTimes["morning"]!
        return (1...times.count).contains(period) ? times[period - 1] : "00:00"
    }

    /// 45-minute periods.
    static func lessonEndTime(session: String, period: Int) -> String {
        let start = lessonStartTime(session: session, period: period).split(separator: ":").compactMap { Int($0) }
        guard start.count == 2 else { return "00:00" }
        let total = start[0] * 60 + start[1] + 45
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func lessonStartTime(_ lesson: Lesson) -> String { lessonStartTime(session: lesson.session, period: lesson.period) }
    static func lessonEndTime(_ lesson: Lesson) -> String { lessonEndTime(session: lesson.session, period: lesson.period) }
    static func periodLabel(_ lesson: Lesson) -> String { periodLabel(session: lesson.session, period: lesson.period) }

    static func compare(_ a: Lesson, _ b: Lesson) -> Bool {
        if a.date != b.date { return a.date < b.date }
        let left = lessonStartTime(a), right = lessonStartTime(b)
        if left != right { return left < right }
        return a.period < b.period
    }

    /// Slots → dated lessons in [from, to] ∩ school year, skipping weekends, holidays and slots not in effect.
    static func expandLessons(_ slots: [TimetableSlot], from: String, to: String, year: TeachingYear, holidays: Set<String>) -> [Lesson] {
        var lessons: [Lesson] = []
        let start = from < year.startDate ? year.startDate : from
        let end = to > year.endDate ? year.endDate : to
        guard !start.isEmpty, !end.isEmpty, start <= end else { return [] }
        var date = start
        var guardDays = 0
        while date <= end, guardDays < 800 {
            guardDays += 1
            defer { date = addDays(date, 1) }
            guard isTimetableDay(date, year: year, holidays: holidays) else { continue }
            let weekday = isoWeekday(date)
            for slot in slots where slot.weekday == weekday && slotCovers(slot, date: date) {
                lessons.append(Lesson(date: date, weekday: weekday, session: slot.session, period: slot.period,
                                      classId: slot.classId, teacherId: slot.teacherId, subjectId: slot.subjectId))
            }
        }
        return lessons.sorted(by: compare)
    }

    /// First lesson per class from now: a lesson of today counts until it ends, then the first later day.
    static func nextLessonByClass(_ lessons: [Lesson], date: String, time: String) -> [String: Lesson] {
        var next: [String: Lesson] = [:]
        for lesson in lessons.sorted(by: compare) {
            if lesson.date < date { continue }
            if lesson.date == date, lessonEndTime(lesson) < time { continue }
            if next[lesson.classId] == nil { next[lesson.classId] = lesson }
        }
        return next
    }

    /// Vietnam calendar date + HH:mm.
    static func vietnamNow(_ now: Date = Date()) -> (date: String, time: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        return (
            String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
            String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        )
    }

    static func clamp(_ date: String, to year: TeachingYear) -> String {
        if date < year.startDate { return year.startDate }
        if date > year.endDate { return year.endDate }
        return date
    }

    struct ClassRow: Equatable, Sendable {
        let teachingClass: TeachingClass
        let next: Lesson?
        let subjectIds: [String]
    }

    /// Lớp giảng dạy: classes sorted by next lesson (nearest first), then classes without one by name.
    static func teachingClassRows(_ data: MyTeaching, now: (date: String, time: String)) -> [ClassRow] {
        let lessons = expandLessons(data.slots, from: now.date, to: addDays(now.date, lookAheadDays), year: data.year, holidays: data.holidays)
        let next = nextLessonByClass(lessons, date: now.date, time: now.time)
        var subjects: [String: [String]] = [:]
        for slot in data.slots where !(subjects[slot.classId] ?? []).contains(slot.subjectId) {
            subjects[slot.classId, default: []].append(slot.subjectId)
        }
        return data.classes
            .map { ClassRow(teachingClass: $0, next: next[$0.id], subjectIds: subjects[$0.id] ?? []) }
            .sorted { a, b in
                switch (a.next, b.next) {
                case let (left?, right?):
                    return "\(left.date) \(lessonStartTime(left))" < "\(right.date) \(lessonStartTime(right))"
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil):
                    return a.teachingClass.name.localizedStandardCompare(b.teachingClass.name) == .orderedAscending
                }
            }
    }

    /// "Hôm nay · Tiết 3 sáng · 08:50" or "Thứ 4, 28/10/2026 · …".
    static func nextLessonText(_ lesson: Lesson?, today: String) -> String {
        guard let lesson else { return "Không còn tiết nào trong 5 tuần tới" }
        let day = lesson.date == today ? "Hôm nay" : "\(weekdayLabel(lesson.date)), \(displayDate(lesson.date))"
        return "\(day) · \(periodLabel(lesson)) · \(lessonStartTime(lesson))"
    }

    /// Lessons a teacher has in one class on one date (Sổ đầu bài "Tiết" choices).
    static func lessons(classId: String, date: String, data: MyTeaching) -> [Lesson] {
        expandLessons(data.slots.filter { $0.classId == classId }, from: date, to: date, year: data.year, holidays: data.holidays)
    }

    /// Default lesson in the Sổ đầu bài sheet: the latest one already started (any lesson on a past date),
    /// otherwise the first lesson of the day.
    static func defaultLesson(_ lessons: [Lesson], date: String, now: (date: String, time: String)) -> Lesson? {
        lessons.reversed().first { date < now.date || lessonStartTime($0) <= now.time } ?? lessons.first
    }

    /// Latest date a lesson can be logged: today, clamped to the school year end.
    static func latestLogDate(today: String, year: TeachingYear) -> String { today > year.endDate ? year.endDate : today }

    static func semesterForDate(_ date: String, semester2StartDate: String) -> Int {
        !semester2StartDate.isEmpty && date >= semester2StartDate ? 2 : 1
    }

    /// dd/MM/yyyy.
    static func displayDate(_ ymd: String) -> String {
        guard let (y, m, d) = components(ymd) else { return ymd }
        return String(format: "%02d/%02d/%04d", d, m, y)
    }

    static func monthTitle(_ ymd: String) -> String {
        guard let (y, m, _) = components(ymd) else { return ymd }
        return "Tháng \(m)/\(y)"
    }

    /// Weekdays (Thứ 2–6) of the calendar weeks covering [monthStart, monthEnd]; earlier dates are padding.
    static func monthGridDates(_ anyDateInMonth: String) -> [String] {
        let from = monthStart(anyDateInMonth), to = monthEnd(anyDateInMonth)
        var dates: [String] = []
        var date = weekStart(from)
        while date <= to {
            if isoWeekday(date) <= 5 { dates.append(date) }
            date = addDays(date, 1)
        }
        return dates
    }

    static func stars(_ rating: Int) -> String {
        let value = max(0, min(5, rating))
        return String(repeating: "★", count: value) + String(repeating: "☆", count: 5 - value)
    }
}

// MARK: - Lịch dạy views, Học bạ grouping, Sổ đầu bài average

enum ScheduleMode: Int, CaseIterable, Sendable {
    case list, week, month

    var title: String {
        switch self {
        case .list: return "Danh sách"
        case .week: return "Tuần"
        case .month: return "Tháng"
        }
    }

    /// Visible range for an anchor date: Danh sách and Tháng = calendar month, Tuần = Thứ 2 → Thứ 6.
    func range(anchor: String) -> (from: String, to: String, label: String) {
        switch self {
        case .week:
            let from = TeachingSchedule.weekStart(anchor)
            let to = TeachingSchedule.addDays(from, 4)
            return (from, to, "Tuần \(TeachingSchedule.displayDate(from)) – \(TeachingSchedule.displayDate(to))")
        case .list, .month:
            return (TeachingSchedule.monthStart(anchor), TeachingSchedule.monthEnd(anchor), TeachingSchedule.monthTitle(anchor))
        }
    }

    func shift(_ anchor: String, by step: Int) -> String {
        self == .week ? TeachingSchedule.addDays(anchor, 7 * step) : TeachingSchedule.addMonths(anchor, step)
    }
}

enum GradebookLayout {
    static let gradeLevels = [6, 7, 8, 9]

    /// Khối 6–9 always (web GradeClassPicker), plus any other grade present; classes in natural name order.
    static func groups(_ classes: [GradebookClassRow]) -> [(grade: Int, classes: [GradebookClassRow])] {
        var byGrade: [Int: [GradebookClassRow]] = Dictionary(uniqueKeysWithValues: gradeLevels.map { ($0, []) })
        for row in classes { byGrade[row.gradeLevel, default: []].append(row) }
        return byGrade.keys.sorted().map { grade in
            (grade, byGrade[grade]!.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    /// "Chủ nhiệm · Toán, Vật lý" or "38 HS".
    static func classMeta(_ row: GradebookClassRow, subjectName: (String) -> String) -> String {
        var parts: [String] = []
        if row.isHomeroom { parts.append("Chủ nhiệm") }
        if !row.subjectIds.isEmpty { parts.append(row.subjectIds.map(subjectName).joined(separator: ", ")) }
        return parts.isEmpty ? "\(row.rosterCount) HS" : parts.joined(separator: " · ")
    }

    /// "8,0 Thường xuyên · 7,5 Giữa kỳ" for one subject and semester; "—" when empty.
    static func scoresText(_ entries: [GradeEntry]) -> String {
        entries.isEmpty ? "—" : entries.map { "\(GradeMath.formatScore($0.score)) \($0.testTypeName)" }.joined(separator: " · ")
    }

    static func semesterTitle(_ semester: Int) -> String { semester == 2 ? "Học kỳ II" : "Học kỳ I" }
}

enum LessonLogSummary {
    /// "4,2" (one decimal, comma) or nil when there is no log.
    static func averageRating(_ ratings: [Int]) -> String? {
        guard !ratings.isEmpty else { return nil }
        let value = Double(ratings.reduce(0, +)) / Double(ratings.count)
        return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Scores (mirror of convex/teachingPolicy.ts)

enum GradeMath {
    /// Điểm số 0–10, at most 2 decimals, comma or dot ("8,5" / "8.5"). nil when invalid.
    static func parseScore(_ text: String) -> Double? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard raw.range(of: #"^\d{1,2}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Double(raw), value >= 0, value <= 10 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// vi-VN, 1–2 decimals: 8 → "8,0", 8.25 → "8,25", nil → "—".
    static func formatScore(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        var text = String(format: "%.2f", (value * 100).rounded() / 100)
        if text.hasSuffix("0") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// Score as typed back into the edit field ("8,5").
    static func editText(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    static func roundAverage(_ value: Double) -> Double { ((value + Double.ulpOfOne) * 10).rounded() / 10 }

    /// ĐTB môn học kỳ = Σ(điểm × hệ số) / Σ hệ số.
    static func semesterAverage(_ entries: [(score: Double, coefficient: Int)]) -> Double? {
        let weights = entries.reduce(0) { $0 + $1.coefficient }
        guard weights > 0 else { return nil }
        let weighted = entries.reduce(0.0) { $0 + $1.score * Double($1.coefficient) }
        return roundAverage(weighted / Double(weights))
    }

    /// ĐTB cả năm = (HK I + 2 × HK II) / 3, only when both exist.
    static func yearAverage(_ semester1: Double?, _ semester2: Double?) -> Double? {
        guard let semester1, let semester2 else { return nil }
        return roundAverage((semester1 + 2 * semester2) / 3)
    }

    static func overallAverage(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return roundAverage(present.reduce(0, +) / Double(present.count))
    }
}

// MARK: - Decoding

enum TeachingDecoder {
    static func invalid() -> ConvexException {
        ConvexException(code: "INVALID_RESPONSE", message: "Phản hồi Lớp học không hợp lệ.")
    }

    static func year(_ value: Any?) throws -> TeachingYear {
        guard let row = value as? [String: Any], let id = row["_id"] as? String, !id.isEmpty else { throw invalid() }
        return TeachingYear(
            id: id, name: row.text("name"), startDate: row.text("startDate"), endDate: row.text("endDate"),
            semester2StartDate: row.text("semester2StartDate"), locked: row.flag("locked")
        )
    }

    static func slots(_ value: Any?) throws -> [TimetableSlot] {
        guard let items = value as? [[String: Any]] else { throw invalid() }
        return try items.map { row in
            let weekday = row.number("weekday"), period = row.number("period")
            let session = row.text("session")
            guard (1...5).contains(weekday), (1...5).contains(period), ["morning", "afternoon"].contains(session),
                  !row.text("classId").isEmpty, !row.text("effectiveFrom").isEmpty else { throw invalid() }
            let to = row.text("effectiveTo")
            return TimetableSlot(
                id: row.text("_id"), classId: row.text("classId"), weekday: weekday, session: session, period: period,
                teacherId: row.text("teacherId"), subjectId: row.text("subjectId"),
                effectiveFrom: row.text("effectiveFrom"), effectiveTo: to.isEmpty ? nil : to
            )
        }
    }

    static func classes(_ value: Any?) -> [TeachingClass] {
        (value as? [[String: Any]] ?? []).compactMap { row in
            let id = row.text("_id")
            guard !id.isEmpty else { return nil }
            return TeachingClass(id: id, name: row.text("name"), gradeLevel: row.number("gradeLevel"), status: row.text("status"))
        }
    }

    static func holidays(_ value: Any?) -> Set<String> { Set(value as? [String] ?? []) }

    static func myTeaching(_ value: [String: Any]) throws -> MyTeaching {
        MyTeaching(
            year: try year(value["year"]),
            today: value.text("today"),
            holidays: holidays(value["holidays"]),
            slots: try slots(value["slots"]),
            classes: classes(value["classes"]),
            todayLogs: logRecords(value["todayLogs"], classId: nil)
        )
    }

    static func logRecords(_ value: Any?, classId: String?) -> [LessonLogRecord] {
        (value as? [[String: Any]] ?? []).map { row in
            LessonLogRecord(
                id: row.text("_id"), classId: classId ?? row.text("classId"), date: row.text("date"),
                session: row.text("session"), period: row.number("period"), rating: row.number("rating"),
                comment: row.text("comment"), updatedAt: row.real("updatedAt")
            )
        }
    }

    static func catalog(_ value: [String: Any]) -> TeachingCatalog {
        TeachingCatalog(
            subjects: subjects(value["subjects"]),
            testTypes: testTypes(value["testTypes"], activeOnly: true)
        )
    }

    static func subjects(_ value: Any?) -> [CatalogSubject] {
        (value as? [[String: Any]] ?? []).map { CatalogSubject(id: $0.text("_id"), name: $0.text("name"), active: $0["active"] as? Bool ?? true) }
    }

    static func testTypes(_ value: Any?, activeOnly: Bool) -> [CatalogTestType] {
        (value as? [[String: Any]] ?? [])
            .filter { !activeOnly || ($0["active"] as? Bool ?? true) }
            .map { CatalogTestType(id: $0.text("_id"), name: $0.text("name"), coefficient: $0.number("coefficient")) }
    }

    static func schedule(_ value: [String: Any]) throws -> TeacherSchedule {
        TeacherSchedule(
            year: try year(value["year"]),
            teacherName: (value["teacher"] as? [String: Any])?.text("name") ?? "",
            holidays: holidays(value["holidays"]),
            slots: try slots(value["slots"]),
            classes: classes(value["classes"])
        )
    }

    static func classLogs(_ value: [String: Any]) throws -> [ClassLessonLog] {
        guard let items = value["items"] as? [[String: Any]] else { throw invalid() }
        return items.map { row in
            ClassLessonLog(
                id: row.text("_id"), date: row.text("date"), session: row.text("session"), period: row.number("period"),
                teacherName: row.text("teacherName"), subjectName: row.text("subjectName"), rating: row.number("rating"),
                comment: row.text("comment"), updatedAt: row.real("updatedAt") ?? 0
            )
        }
    }

    static func gradebookClasses(_ value: [String: Any]) throws -> [GradebookClassRow] {
        guard let items = value["classes"] as? [[String: Any]] else { throw invalid() }
        return items.map { row in
            GradebookClassRow(
                id: row.text("_id"), name: row.text("name"), gradeLevel: row.number("gradeLevel"),
                rosterCount: row.number("rosterCount"), isHomeroom: row.flag("isHomeroom"),
                subjectIds: row["subjectIds"] as? [String] ?? []
            )
        }
    }

    static func classStudents(_ value: [String: Any]) throws -> GradebookClassStudents {
        guard let klass = value["class"] as? [String: Any], let items = value["students"] as? [[String: Any]] else { throw invalid() }
        return GradebookClassStudents(
            classId: klass.text("_id"), className: klass.text("name"), gradeLevel: klass.number("gradeLevel"),
            yearName: (value["year"] as? [String: Any])?.text("name") ?? "",
            students: items.map { row in
                GradebookStudent(
                    id: row.text("_id"), fullName: row.text("fullName"), studentCode: row.text("studentCode"),
                    dateOfBirth: row.text("dateOfBirth"), rosterNumber: row["rosterNumber"] is NSNumber ? row.number("rosterNumber") : nil
                )
            }
        )
    }

    static func averages(_ row: [String: Any]?) -> GradeAverages {
        GradeAverages(semester1: row?.real("semester1"), semester2: row?.real("semester2"), year: row?.real("year"))
    }

    static func studentRecord(_ value: [String: Any]) throws -> StudentRecord {
        guard let student = value["student"] as? [String: Any], let years = value["years"] as? [[String: Any]],
              let summary = value["summary"] as? [String: Any] else { throw invalid() }
        var yearSummaries: [String: GradeAverages] = [:]
        for row in value["yearSummaries"] as? [[String: Any]] ?? [] { yearSummaries[row.text("schoolYearId")] = averages(row) }
        var subjectSummaries: [String: GradeAverages] = [:]
        for row in summary["subjects"] as? [[String: Any]] ?? [] { subjectSummaries[row.text("subjectId")] = averages(row) }
        return StudentRecord(
            studentId: student.text("_id"), fullName: student.text("fullName"), studentCode: student.text("studentCode"),
            dateOfBirth: student.text("dateOfBirth"),
            years: years.map { row in
                GradeRecordYear(
                    id: row.text("_id"), name: row.text("name"), semester2StartDate: row.text("semester2StartDate"),
                    locked: row.flag("locked"), classId: row.text("classId"), className: row.text("className"),
                    gradeLevel: row.number("gradeLevel")
                )
            },
            yearSummaries: yearSummaries,
            selectedYearId: value.text("selectedYearId"),
            selectedClassId: value.text("selectedClassId"),
            fullView: value.flag("fullView"),
            subjects: subjects(value["subjects"]),
            testTypes: testTypes(value["testTypes"], activeOnly: false),
            subjectIds: value["subjectIds"] as? [String] ?? [],
            writableSubjectIds: value["writableSubjectIds"] as? [String] ?? [],
            subjectSummaries: subjectSummaries,
            summary: averages(summary),
            entries: (value["entries"] as? [[String: Any]] ?? []).map { row in
                GradeEntry(
                    id: row.text("_id"), subjectId: row.text("subjectId"), semester: row.number("semester"),
                    testTypeId: row.text("testTypeId"), testTypeName: row.text("testTypeName"),
                    coefficient: row.number("coefficient"), score: row.real("score") ?? 0,
                    createdAt: row.real("createdAt") ?? 0, enteredByName: row.text("enteredByName"), canEdit: row.flag("canEdit")
                )
            }
        )
    }

    static func absenceOverview(_ value: [String: Any]) throws -> TeachingAbsenceOverview {
        guard let classes = value["classes"] as? [[String: Any]] else { throw invalid() }
        let counts = (value["summary"] as? [String: Any])?["counts"] as? [String: Any] ?? [:]
        func absent(_ row: [String: Any]) -> (Int, Int, Int) {
            let excused = row.number("absent_excused"), unexcused = row.number("absent_unexcused")
            return (excused + unexcused + row.number("absent_pending"), excused, unexcused)
        }
        let total = absent(counts)
        return TeachingAbsenceOverview(
            date: value.text("date"),
            schoolWide: value.text("mode") == "school",
            classes: classes.map { row in
                let rowCounts = absent(row["counts"] as? [String: Any] ?? [:])
                return .init(id: row.text("_id"), name: row.text("name").isEmpty ? row.text("code") : row.text("name"),
                             rosterCount: row.number("rosterCount"), saved: row.flag("saved"),
                             excused: rowCounts.1, unexcused: rowCounts.2, absent: rowCounts.0)
            },
            absent: total.0, excused: total.1, unexcused: total.2
        )
    }
}

// MARK: - Payloads

enum TeachingPayload {
    static func lessonLog(classId: String, date: String, lesson: Lesson, rating: Int, comment: String) throws -> [String: Any] {
        guard (1...5).contains(rating) else { throw ConvexException(code: "INVALID_RATING") }
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 1000 else { throw ConvexException(code: "INVALID_LESSON_COMMENT") }
        return ["classId": classId, "date": date, "session": lesson.session, "period": lesson.period, "rating": rating, "comment": text]
    }

    static func addScore(record: StudentRecord, subjectId: String, semester: Int, testTypeId: String, scoreText: String) throws -> [String: Any] {
        guard let score = GradeMath.parseScore(scoreText) else { throw ConvexException(code: "INVALID_SCORE") }
        guard record.writableSubjectIds.contains(subjectId) else { throw ConvexException(code: "GRADE_SUBJECT_FORBIDDEN") }
        guard [1, 2].contains(semester) else { throw ConvexException(code: "INVALID_SEMESTER") }
        guard !testTypeId.isEmpty else { throw ConvexException(code: "TEST_TYPE_NOT_FOUND") }
        return ["studentId": record.studentId, "classId": record.selectedClassId, "subjectId": subjectId,
                "semester": semester, "testTypeId": testTypeId, "score": score]
    }

    static func updateScore(entry: GradeEntry, semester: Int, testTypeId: String, scoreText: String) throws -> [String: Any] {
        guard let score = GradeMath.parseScore(scoreText) else { throw ConvexException(code: "INVALID_SCORE") }
        guard [1, 2].contains(semester) else { throw ConvexException(code: "INVALID_SEMESTER") }
        return ["id": entry.id, "semester": semester, "testTypeId": testTypeId.isEmpty ? entry.testTypeId : testTypeId, "score": score]
    }
}

// MARK: - Repository

final class TeachingRepository: Sendable {
    private let convex: ConvexHttpClient

    init(convex: ConvexHttpClient) { self.convex = convex }

    func schoolYears() async throws -> [SchoolYear] {
        try HomeroomRepository.decodeSchoolYears(await convex.query("schoolYears:list"))
    }

    func myTeaching(yearId: String) async throws -> MyTeaching {
        try TeachingDecoder.myTeaching(await convex.query("lessonLogs:myTeaching", args: ["schoolYearId": yearId]))
    }

    func catalog() async throws -> TeachingCatalog {
        TeachingDecoder.catalog(try await convex.query("teachingCatalog:catalog"))
    }

    func myLogs(classId: String, date: String) async throws -> [LessonLogRecord] {
        let value = try await convex.query("lessonLogs:myLogsFor", args: ["classId": classId, "date": date])
        return TeachingDecoder.logRecords(value["items"], classId: classId).map {
            LessonLogRecord(id: $0.id, classId: classId, date: date, session: $0.session, period: $0.period,
                            rating: $0.rating, comment: $0.comment, updatedAt: $0.updatedAt)
        }
    }

    func saveLog(_ args: [String: Any]) async throws {
        _ = try await convex.mutation("lessonLogs:save", args: args)
    }

    func classLogs(classId: String, from: String, to: String) async throws -> [ClassLessonLog] {
        try TeachingDecoder.classLogs(await convex.query("lessonLogs:listForClass", args: ["classId": classId, "from": from, "to": to]))
    }

    func schedule(yearId: String) async throws -> TeacherSchedule {
        try TeachingDecoder.schedule(await convex.query("teachers:schedule", args: ["schoolYearId": yearId]))
    }

    func absenceOverview(yearId: String, date: String) async throws -> TeachingAbsenceOverview {
        try TeachingDecoder.absenceOverview(await convex.query("homeroomReports:overview", args: ["schoolYearId": yearId, "date": date]))
    }

    func gradebookClasses(yearId: String) async throws -> [GradebookClassRow] {
        try TeachingDecoder.gradebookClasses(await convex.query("gradebook:myClasses", args: ["schoolYearId": yearId]))
    }

    func classStudents(classId: String) async throws -> GradebookClassStudents {
        try TeachingDecoder.classStudents(await convex.query("gradebook:classStudents", args: ["classId": classId]))
    }

    func studentRecord(studentId: String, yearId: String?) async throws -> StudentRecord {
        var args: [String: Any] = ["studentId": studentId]
        if let yearId, !yearId.isEmpty { args["schoolYearId"] = yearId }
        return try TeachingDecoder.studentRecord(await convex.query("gradebook:studentRecord", args: args))
    }

    func addScore(_ args: [String: Any]) async throws { _ = try await convex.mutation("gradebook:addEntry", args: args) }
    func updateScore(_ args: [String: Any]) async throws { _ = try await convex.mutation("gradebook:updateEntry", args: args) }
    func removeScore(id: String) async throws { _ = try await convex.mutation("gradebook:removeEntry", args: ["id": id]) }
}

private extension Dictionary where Key == String, Value == Any {
    func text(_ key: String) -> String { self[key] as? String ?? "" }
    func flag(_ key: String) -> Bool { self[key] as? Bool ?? false }
    func number(_ key: String) -> Int { (self[key] as? NSNumber)?.intValue ?? 0 }
    func real(_ key: String) -> Double? { self[key] is NSNull ? nil : (self[key] as? NSNumber)?.doubleValue }
}

import Foundation

/// Bán trú (web `src/boarding/*`, backend `convex/boarding.ts`). Pure Foundation: models, strict decoding,
/// the shared "Học kỳ N · Năm học …" label, visibility, form validation and mutation payloads. The server
/// enforces every rule again (`boarding:write` for periods, Báo cáo access for the participant list).

struct BoardingPeriodSummary: Identifiable, Equatable, Sendable {
    let id: String
    let semester: Int
    let schoolYear: String
    let participantCount: Int
}

struct BoardingPerson: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let email: String
    let departmentName: String
    let positionName: String
}

struct BoardingGroup: Equatable, Sendable {
    let departmentName: String
    let participants: [BoardingPerson]
}

/// `boarding:report`: the list a user may read (own department, or the whole school with `view_all`).
struct BoardingReport: Equatable, Sendable {
    let isSchoolWide: Bool
    let periods: [BoardingPeriodSummary]
    let selectedPeriod: BoardingPeriodSummary?
    let groups: [BoardingGroup]
    let totalParticipants: Int
}

struct BoardingAdminPeriod: Identifiable, Equatable, Sendable {
    let id: String
    let semester: Int
    let schoolYear: String
    let participantUserIds: [String]
    let participants: [BoardingPerson]
}

/// `boarding:listAdmin` (admin/mod only).
struct BoardingAdminData: Equatable, Sendable {
    let users: [BoardingPerson]
    let periods: [BoardingAdminPeriod]
}

struct BoardingForm: Equatable, Sendable {
    var semester: Int
    var schoolYear: String
    var participantUserIds: [String]
}

enum Boarding {
    // MARK: Labels

    /// Web `boardingPeriodLabel`: "Học kỳ 1 · Năm học 2026-2027"; `short` drops the year.
    static func periodLabel(semester: Int, schoolYear: String, short: Bool = false) -> String {
        let term = "Học kỳ \(semester)"
        let year = schoolYear.trimmingCharacters(in: .whitespacesAndNewlines)
        return short || year.isEmpty ? term : "\(term) · Năm học \(year)"
    }

    static func periodLabel(_ period: BoardingPeriodSummary?) -> String {
        guard let period else { return "Chưa có kỳ bán trú" }
        return periodLabel(semester: period.semester, schoolYear: period.schoolYear)
    }

    static func scopeText(_ report: BoardingReport) -> String {
        report.isSchoolWide
            ? "Bạn đang xem toàn bộ phòng ban tham gia bán trú."
            : "Bạn đang xem giáo viên tham gia bán trú trong phòng ban của mình."
    }

    // MARK: Visibility (UX only; the server re-checks)

    /// Danh sách tham gia: Báo cáo menu not hidden, or admin/mod (web `isPrimaryMenuVisible('boarding')`).
    static func canSeeParticipants(_ session: UserSession) -> Bool {
        session.canWork && (session.isOperationalManager || (session.menuAccess["reports"] ?? .hidden) != .hidden)
    }

    /// Kỳ bán trú management: operational managers only (`boarding:write`).
    static func canManagePeriods(_ session: UserSession) -> Bool {
        session.canWork && session.isOperationalManager
    }

    // MARK: School years

    /// School year containing `now` (Vietnam time): from July it is "YYYY-(YYYY+1)", before July the previous one.
    static func currentSchoolYear(now: Date = Date()) -> String {
        let base = baseYear(now: now)
        return "\(base)-\(base + 1)"
    }

    /// Web `schoolYearOptions`: two years back to four ahead of the current school year.
    static func schoolYearOptions(now: Date = Date(), including extra: String? = nil) -> [String] {
        let base = baseYear(now: now)
        var options = (0..<7).map { index -> String in
            let start = base - 2 + index
            return "\(start)-\(start + 1)"
        }
        if let extra, !extra.isEmpty, !options.contains(extra) {
            options.append(extra)
            options.sort()
        }
        return options
    }

    static func emptyForm(now: Date = Date()) -> BoardingForm {
        BoardingForm(semester: 1, schoolYear: currentSchoolYear(now: now), participantUserIds: [])
    }

    /// Empty state when the server has no period for the current school year.
    static func hasPeriod(forSchoolYear year: String, in periods: [BoardingPeriodSummary]) -> Bool {
        periods.contains { $0.schoolYear == year }
    }

    private static func baseYear(now: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600) ?? .current
        let parts = calendar.dateComponents([.year, .month], from: now)
        let year = parts.year ?? 2026
        return (parts.month ?? 1) >= 7 ? year : year - 1
    }

    // MARK: Validation + payloads (mirror `cleanInput`; the server re-validates)

    static func validate(_ form: BoardingForm) -> String? {
        if form.semester != 1 && form.semester != 2 { return message(for: "INVALID_SEMESTER") }
        if !isValidSchoolYear(form.schoolYear) { return message(for: "INVALID_SCHOOL_YEAR") }
        if cleanedParticipants(form.participantUserIds).isEmpty { return message(for: "BOARDING_TEACHERS_REQUIRED") }
        return nil
    }

    static func isValidSchoolYear(_ raw: String) -> Bool {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let start = Int(parts[0]), let end = Int(parts[1]) else { return false }
        return end == start + 1
    }

    static func cleanedParticipants(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// `boarding:create` (no id) / `boarding:update` (with id) arguments.
    static func mutationArgs(_ form: BoardingForm, id: String? = nil) -> [String: Any] {
        var args: [String: Any] = [
            "semester": form.semester,
            "schoolYear": form.schoolYear.trimmingCharacters(in: .whitespacesAndNewlines),
            "participantUserIds": cleanedParticipants(form.participantUserIds),
        ]
        if let id, !id.isEmpty { args["id"] = id }
        return args
    }

    static func deletePrompt(_ period: BoardingAdminPeriod) -> String {
        "Xóa \(periodLabel(semester: period.semester, schoolYear: period.schoolYear))?"
    }

    // MARK: Errors (web BoardingManagement `errorMessage`)

    static var codes: [String] { ConvexHttpClient.boardingCodes }

    static func message(for code: String) -> String? { ConvexHttpClient.boardingMessage(code) }

    /// Management fallback mirrors the web ("Không thể hoàn tất thao tác…").
    static func errorMessage(_ error: Error, fallback: String = "Không thể hoàn tất thao tác. Vui lòng thử lại.") -> String {
        let raw = (error as? ConvexException).map { "\($0.code) \($0.message)" } ?? String(describing: error)
        if let code = codes.first(where: { raw.contains($0) }), let message = message(for: code) { return message }
        if let convex = error as? ConvexException, convex.code == "FORBIDDEN" || convex.code.contains("FORBIDDEN") {
            return "Bạn không có quyền xem Bán trú."
        }
        if let convex = error as? ConvexException, ["USER_NOT_ACTIVE", "PASSWORD_CHANGE_REQUIRED", "UNAUTHENTICATED"].contains(convex.code) {
            return convex.message
        }
        return fallback
    }

    // MARK: Decoding

    static func decodeReport(_ value: [String: Any]) throws -> BoardingReport {
        guard let scope = value["visibilityScope"] as? String, scope == "all" || scope == "department",
              let rawPeriods = value["periods"] as? [[String: Any]],
              let rawGroups = value["groups"] as? [[String: Any]] else { throw invalid() }
        let periods = try rawPeriods.map(decodeSummary)
        var selected: BoardingPeriodSummary?
        if let raw = value["selectedPeriod"] as? [String: Any] {
            let id = try requiredId(raw["_id"])
            // The selected row carries no count; reuse the list row when present.
            let rowSemester = try semester(raw["semester"])
            let rowYear = try schoolYear(raw["schoolYear"])
            selected = periods.first { $0.id == id } ?? BoardingPeriodSummary(
                id: id,
                semester: rowSemester,
                schoolYear: rowYear,
                participantCount: 0
            )
        } else if !(value["selectedPeriod"] is NSNull) && value["selectedPeriod"] != nil {
            throw invalid()
        }
        let groups = try rawGroups.map { group -> BoardingGroup in
            guard let name = group["departmentName"] as? String,
                  let people = group["participants"] as? [[String: Any]] else { throw invalid() }
            return BoardingGroup(departmentName: name, participants: try people.map(decodePerson))
        }
        let total = int(value["totalParticipants"]) ?? groups.reduce(0) { $0 + $1.participants.count }
        return BoardingReport(
            isSchoolWide: scope == "all",
            periods: periods,
            selectedPeriod: selected,
            groups: groups,
            totalParticipants: total
        )
    }

    static func decodeAdmin(_ value: [String: Any]) throws -> BoardingAdminData {
        guard let rawUsers = value["users"] as? [[String: Any]],
              let rawPeriods = value["periods"] as? [[String: Any]] else { throw invalid() }
        let users = try rawUsers.map(decodePerson)
        let periods = try rawPeriods.map { row -> BoardingAdminPeriod in
            guard let ids = row["participantUserIds"] as? [String] else { throw invalid() }
            return BoardingAdminPeriod(
                id: try requiredId(row["_id"]),
                semester: try semester(row["semester"]),
                schoolYear: try schoolYear(row["schoolYear"]),
                participantUserIds: ids,
                participants: try ((row["participants"] as? [[String: Any]]) ?? []).map(decodePerson)
            )
        }
        return BoardingAdminData(users: users, periods: periods)
    }

    private static func decodeSummary(_ row: [String: Any]) throws -> BoardingPeriodSummary {
        BoardingPeriodSummary(
            id: try requiredId(row["_id"]),
            semester: try semester(row["semester"]),
            schoolYear: try schoolYear(row["schoolYear"]),
            participantCount: int(row["participantCount"]) ?? 0
        )
    }

    private static func decodePerson(_ row: [String: Any]) throws -> BoardingPerson {
        let name = ((row["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (row["email"] as? String) ?? ""
        return BoardingPerson(
            id: try requiredId(row["_id"]),
            name: name.isEmpty ? (email.isEmpty ? "Chưa đặt tên" : email) : name,
            email: email,
            departmentName: (row["departmentName"] as? String) ?? "",
            positionName: (row["positionName"] as? String) ?? ""
        )
    }

    private static func requiredId(_ value: Any?) throws -> String {
        guard let id = value as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid() }
        return id
    }

    private static func semester(_ value: Any?) throws -> Int {
        guard let semester = int(value), semester == 1 || semester == 2 else { throw invalid() }
        return semester
    }

    private static func schoolYear(_ value: Any?) throws -> String {
        guard let year = value as? String, isValidSchoolYear(year) else { throw invalid() }
        return year
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !(value is Bool) else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double else { return nil }
        return number.intValue
    }

    private static func invalid() -> ConvexException {
        ConvexException(code: "BOARDING_INVALID_RESPONSE", message: "Dữ liệu bán trú không hợp lệ. Vui lòng thử lại.")
    }
}

/// Exact Convex endpoints used by the Bán trú screen (same as the web).
enum BoardingEndpoint {
    static let report = "boarding:report"
    static let listAdmin = "boarding:listAdmin"
    static let create = "boarding:create"
    static let update = "boarding:update"
    static let remove = "boarding:remove"
}

final class BoardingRepository: Sendable {
    private let convex: ConvexHttpClient

    init(convex: ConvexHttpClient) {
        self.convex = convex
    }

    func report(periodId: String?) async throws -> BoardingReport {
        var args: [String: Any] = [:]
        if let periodId, !periodId.isEmpty { args["periodId"] = periodId }
        return try Boarding.decodeReport(try await convex.query(BoardingEndpoint.report, args: args))
    }

    func listAdmin() async throws -> BoardingAdminData {
        try Boarding.decodeAdmin(try await convex.query(BoardingEndpoint.listAdmin))
    }

    func save(_ form: BoardingForm, id: String?) async throws {
        if let message = Boarding.validate(form) {
            throw ConvexException(code: "VALIDATION", message: message)
        }
        let isUpdate = !(id ?? "").isEmpty
        _ = try await convex.mutation(isUpdate ? BoardingEndpoint.update : BoardingEndpoint.create, args: Boarding.mutationArgs(form, id: id))
    }

    func remove(id: String) async throws {
        _ = try await convex.mutation(BoardingEndpoint.remove, args: ["id": id])
    }
}

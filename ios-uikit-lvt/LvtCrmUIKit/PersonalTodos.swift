import Foundation

/// "Việc của tôi": private to-dos for every active account, owner-only on the server (convex/personalTodos.ts).
/// Foundation only (models, decoding, form validation, repository) so it is checkable offline.

struct PersonalTodo: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let note: String
    let dueAt: Int64?
    let remindAt: Int64?
    let remindedAt: Int64?
    let completedAt: Int64?
    let createdAt: Int64
    let updatedAt: Int64

    var isCompleted: Bool { completedAt != nil }
}

struct PersonalTodoList: Equatable, Sendable {
    let open: [PersonalTodo]
    let completed: [PersonalTodo]

    static let empty = PersonalTodoList(open: [], completed: [])

    func contains(_ id: String) -> Bool { open.contains { $0.id == id } || completed.contains { $0.id == id } }
}

/// Editable form values. Times are epoch milliseconds, minute precision (like the web datetime-local input).
struct PersonalTodoForm: Equatable {
    var title = ""
    var note = ""
    var dueAt: Int64?
    var remindAt: Int64?

    init() {}

    init(_ todo: PersonalTodo) {
        title = todo.title
        note = todo.note
        dueAt = todo.dueAt
        remindAt = todo.remindAt
    }
}

struct PersonalTodoValidation: Equatable {
    var errors: [String: String] = [:]
    var ok: Bool { errors.isEmpty }
}

enum PersonalTodos {
    static let titleMax = 200
    static let noteMax = 2000
    /// Push / bell `sourceType` for reminders; push `kind` is `todo`.
    static let notificationSourceType = "todo_reminder"
    static let notificationKind = "todo"
    static let intro = "Danh sách việc riêng của bạn. Chỉ bạn nhìn thấy, không cần duyệt và không liên quan đến công văn."

    static func decodeList(_ value: [String: Any]) throws -> PersonalTodoList {
        guard let open = value["open"] as? [[String: Any]], let completed = value["completed"] as? [[String: Any]] else { throw invalid() }
        return PersonalTodoList(open: try open.map(decodeTodo), completed: try completed.map(decodeTodo))
    }

    static func decodeTodo(_ row: [String: Any]) throws -> PersonalTodo {
        guard let id = row["_id"] as? String, !id.isEmpty, let title = row["title"] as? String else { throw invalid() }
        func time(_ key: String) throws -> Int64? {
            switch row[key] {
            case nil, is NSNull: return nil
            case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
                let value = number.doubleValue
                guard value.isFinite, value >= 0 else { throw invalid() }
                return Int64(value)
            default: throw invalid()
            }
        }
        return PersonalTodo(
            id: id,
            title: title,
            note: row["note"] as? String ?? "",
            dueAt: try time("dueAt"),
            remindAt: try time("remindAt"),
            remindedAt: try time("remindedAt"),
            completedAt: try time("completedAt"),
            createdAt: try time("createdAt") ?? 0,
            updatedAt: try time("updatedAt") ?? 0
        )
    }

    /// Mirrors web `validateTodoForm`: field errors shown under each input plus the create/update payload.
    /// An unchanged reminder that already fired may stay (the server accepts it too).
    static func validate(_ form: PersonalTodoForm, now: Int64, previousRemindAt: Int64? = nil) -> PersonalTodoValidation {
        var result = PersonalTodoValidation()
        let title = trimmed(form.title)
        if title.isEmpty { result.errors["title"] = "Vui lòng nhập tên việc." }
        else if title.utf16.count > titleMax { result.errors["title"] = "Tên việc tối đa \(titleMax) ký tự." }
        if trimmed(form.note).utf16.count > noteMax { result.errors["note"] = "Ghi chú tối đa \(noteMax) ký tự." }
        if let due = form.dueAt, due <= 0 { result.errors["due"] = "Hạn chót không hợp lệ." }
        if let remind = form.remindAt {
            if remind <= 0 { result.errors["remind"] = "Giờ nhắc không hợp lệ." }
            else if remind <= now && remind != previousRemindAt { result.errors["remind"] = "Giờ nhắc phải ở tương lai." }
        }
        return result
    }

    /// `personalTodos.create` / `.update` args. Cleared fields are sent as null (the server clears them).
    static func payload(_ form: PersonalTodoForm, id: String? = nil) -> [String: Any] {
        let note = trimmed(form.note)
        var args: [String: Any] = [
            "title": trimmed(form.title),
            "note": note.isEmpty ? NSNull() : note,
            "dueAt": form.dueAt.map { NSNumber(value: $0) } ?? NSNull(),
            "remindAt": form.remindAt.map { NSNumber(value: $0) } ?? NSNull(),
        ]
        if let id { args["id"] = id }
        return args
    }

    /// Date picker value → epoch ms truncated to the minute.
    static func minuteMs(_ date: Date) -> Int64 {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        return ms - ((ms % 60_000) + 60_000) % 60_000
    }

    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }

    /// Epoch ms → `HH:mm dd/MM/yyyy` (Vietnam time), like the web.
    static func formatMoment(_ ms: Int64?) -> String {
        guard let ms, ms > 0 else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = VietnamDate.timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date(ms))
        return String(format: "%02d:%02d %02d/%02d/%04d", parts.hour ?? 0, parts.minute ?? 0, parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
    }

    static func isOverdue(_ todo: PersonalTodo, now: Int64) -> Bool {
        !todo.isCompleted && (todo.dueAt.map { $0 < now } ?? false)
    }

    /// One main status ("Hoàn thành" / "Quá hạn") plus the time lines shown under the title.
    static func status(_ todo: PersonalTodo, now: Int64) -> String? {
        if todo.isCompleted { return "Hoàn thành" }
        return isOverdue(todo, now: now) ? "Quá hạn" : nil
    }

    static func metaLines(_ todo: PersonalTodo) -> [String] {
        var lines = [todo.dueAt.map { "Hạn chót \(formatMoment($0))" } ?? "Không có hạn chót"]
        if let remind = todo.remindAt { lines.append("Nhắc lúc \(formatMoment(remind))") }
        if let done = todo.completedAt { lines.append("Xong lúc \(formatMoment(done))") }
        return lines
    }

    static func deletePrompt(_ todo: PersonalTodo) -> String {
        "Xóa việc “\(todo.title)”? Việc sẽ biến mất khỏi danh sách và không còn nhắc."
    }

    static func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func invalid() -> ConvexException {
        ConvexException(code: "INVALID_RESPONSE", message: "Phản hồi danh sách việc không hợp lệ.")
    }
}

final class PersonalTodoRepository: Sendable {
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

    func listMine() async throws -> PersonalTodoList {
        try PersonalTodos.decodeList(await query("personalTodos:listMine", [:]))
    }

    /// Returns the new todo id.
    @discardableResult
    func create(_ form: PersonalTodoForm) async throws -> String {
        let value = try await mutation("personalTodos:create", PersonalTodos.payload(form))
        guard let id = value["value"] as? String, !id.isEmpty else { throw ConvexException(code: "INVALID_MUTATION_ACK", message: "Chưa xác nhận được việc vừa thêm. Tải lại để kiểm tra trước khi thêm lại.") }
        return id
    }

    func update(id: String, form: PersonalTodoForm) async throws {
        _ = try await mutation("personalTodos:update", PersonalTodos.payload(form, id: id))
    }

    func setCompleted(id: String, done: Bool) async throws {
        _ = try await mutation("personalTodos:setCompleted", ["id": id, "done": done])
    }

    func remove(id: String) async throws {
        _ = try await mutation("personalTodos:remove", ["id": id])
    }
}

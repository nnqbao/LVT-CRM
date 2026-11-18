import Foundation

/// Offline checks for "Việc của tôi": decoding, form validation/payload, display helpers, repository endpoints
/// and reminder push routing keys. Injected fixtures only: no network, credentials or app launch.
@main
struct PersonalTodoChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { checks += 1; precondition(condition, message) }
        func rejects(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); check(false, message) } catch { check(true, message) }
        }

        // 2026-10-07 08:30 Asia/Ho_Chi_Minh = 01:30Z.
        let due: Int64 = 1_791_336_600_000
        let now: Int64 = due - 3_600_000
        func row(_ id: String, completed: Int64? = nil, dueAt: Any = NSNull(), remindAt: Any = NSNull()) -> [String: Any] {
            ["_id": id, "title": "Việc \(id)", "note": "", "dueAt": dueAt, "remindAt": remindAt, "remindedAt": NSNull(), "completedAt": completed.map { NSNumber(value: $0) } ?? NSNull(), "createdAt": 1, "updatedAt": 2]
        }
        let list = try PersonalTodos.decodeList(["open": [row("a", dueAt: due), row("b")], "completed": [row("c", completed: due)]])
        check(list.open.map(\.id) == ["a", "b"] && list.completed.map(\.id) == ["c"] && list.contains("c") && !list.contains("z"), "Open/completed decoded in server order")
        check(list.open[0].dueAt == due && list.open[1].dueAt == nil && list.completed[0].isCompleted, "Nullable times")
        rejects({ _ = try PersonalTodos.decodeList(["open": [row("")], "completed": []]) }, "Empty id")
        rejects({ _ = try PersonalTodos.decodeList(["open": [row("a", dueAt: "soon")], "completed": []]) }, "Non-numeric time")
        rejects({ _ = try PersonalTodos.decodeList(["open": [row("a", dueAt: true)], "completed": []]) }, "Boolean time")
        rejects({ _ = try PersonalTodos.decodeList(["open": []]) }, "Missing completed")

        // Display mirrors the web: HH:mm dd/MM/yyyy in Vietnam time, one main status.
        check(PersonalTodos.formatMoment(due) == "08:30 07/10/2026", "Vietnam time format")
        check(PersonalTodos.formatMoment(nil).isEmpty, "No time")
        check(PersonalTodos.isOverdue(list.open[0], now: due + 1) && !PersonalTodos.isOverdue(list.open[0], now: now) && !PersonalTodos.isOverdue(list.open[1], now: due + 1), "Overdue only with a past due")
        check(PersonalTodos.status(list.open[0], now: due + 1) == "Quá hạn" && PersonalTodos.status(list.completed[0], now: due + 1) == "Hoàn thành" && PersonalTodos.status(list.open[1], now: now) == nil, "Status pill")
        check(PersonalTodos.metaLines(list.open[1]) == ["Không có hạn chót"], "Undated meta")
        check(PersonalTodos.metaLines(list.completed[0]).last == "Xong lúc 08:30 07/10/2026", "Completed meta")
        check(PersonalTodos.deletePrompt(list.open[0]) == "Xóa việc “Việc a”? Việc sẽ biến mất khỏi danh sách và không còn nhắc.", "Delete confirmation wording")

        // Validation (web validateTodoForm) + payload (nulls clear fields).
        var form = PersonalTodoForm()
        check(PersonalTodos.validate(form, now: now).errors["title"] == "Vui lòng nhập tên việc.", "Title required")
        form.title = String(repeating: "x", count: 201)
        check(PersonalTodos.validate(form, now: now).errors["title"] == "Tên việc tối đa 200 ký tự.", "Title ≤ 200")
        form.title = "  Soạn giáo án  "
        form.note = String(repeating: "n", count: 2001)
        check(PersonalTodos.validate(form, now: now).errors["note"] == "Ghi chú tối đa 2000 ký tự.", "Note ≤ 2000")
        form.note = "  ghi chú  "
        form.remindAt = now - 60_000
        check(PersonalTodos.validate(form, now: now).errors["remind"] == "Giờ nhắc phải ở tương lai.", "New reminder must be future")
        check(PersonalTodos.validate(form, now: now, previousRemindAt: now - 60_000).ok, "Unchanged fired reminder may stay")
        form.remindAt = now + 60_000
        form.dueAt = due
        check(PersonalTodos.validate(form, now: now).ok, "Valid form")
        let create = PersonalTodos.payload(form)
        check(create["title"] as? String == "Soạn giáo án" && create["note"] as? String == "ghi chú" && (create["dueAt"] as? NSNumber)?.int64Value == due && create["id"] == nil, "Create payload trimmed")
        var cleared = form; cleared.note = " "; cleared.dueAt = nil; cleared.remindAt = nil
        let update = PersonalTodos.payload(cleared, id: "a")
        check(update["id"] as? String == "a" && update["note"] is NSNull && update["dueAt"] is NSNull && update["remindAt"] is NSNull, "Update clears with null")
        check(Set(update.keys) == ["id", "title", "note", "dueAt", "remindAt"], "Exact update keys")
        let edited = PersonalTodoForm(list.open[0])
        check(edited.title == "Việc a" && edited.dueAt == due, "Edit form prefilled")
        let picked = PersonalTodos.minuteMs(Date(timeIntervalSince1970: 1_791_336_637.9))
        check(picked == due, "Picker value truncated to the minute")

        // Repository endpoints (owner-only on the server; the app never sends a user id).
        let fixture = TodoFixture(list: ["open": [row("a")], "completed": [[String: Any]]()])
        let repository = PersonalTodoRepository(query: fixture.query, mutation: fixture.mutation)
        _ = try await repository.listMine()
        let id = try await repository.create(form)
        try await repository.update(id: "a", form: cleared)
        try await repository.setCompleted(id: "a", done: true)
        try await repository.remove(id: "a")
        check(fixture.calls.map(\.0) == ["personalTodos:listMine", "personalTodos:create", "personalTodos:update", "personalTodos:setCompleted", "personalTodos:remove"], "Exact endpoints")
        check(id == "new-id" && fixture.calls[0].1.isEmpty, "Create returns id; listMine has no args")
        check(fixture.calls[3].1["done"] as? Bool == true && fixture.calls[4].1["id"] as? String == "a", "setCompleted/remove args")
        check(fixture.calls.allSatisfy { $0.1["userId"] == nil }, "Never sends a user id")
        fixture.createAck = [:]
        do { _ = try await repository.create(form); check(false, "Create without id") } catch { check((error as? ConvexException)?.code == "INVALID_MUTATION_ACK", "Unacknowledged create is not success") }

        // Server codes → Vietnamese (INVALID_TODO_* must never read as a login error).
        for (raw, message) in [
            ("INVALID_TODO_TITLE", "Vui lòng nhập tên việc (tối đa 200 ký tự)."),
            ("INVALID_TODO_NOTE", "Ghi chú tối đa 2000 ký tự."),
            ("INVALID_TODO_TIME", "Thời gian không hợp lệ."),
            ("TODO_REMIND_IN_PAST", "Giờ nhắc phải ở tương lai."),
            ("TODO_NOT_FOUND", "Việc này không còn tồn tại."),
        ] {
            check(ConvexHttpClient.humanize("Uncaught Error: \(raw)") == message, "Message for \(raw)")
        }

        // Reminder push/bell keys used by routing (kind `todo`, sourceType `todo_reminder`).
        check(PersonalTodos.notificationKind == "todo" && PersonalTodos.notificationSourceType == "todo_reminder", "Reminder routing keys")
        print("PASS \(checks) Việc của tôi offline checks (decode, display, validation, payload, repository, errors); no network/app launch")
    }
}

private final class TodoFixture: @unchecked Sendable {
    let list: [String: Any]
    var calls: [(String, [String: Any])] = []
    var createAck: [String: Any] = ["value": "new-id"]
    init(list: [String: Any]) { self.list = list }

    func query(_ path: String, _ args: [String: Any]) async throws -> [String: Any] {
        calls.append((path, args))
        guard path == "personalTodos:listMine" else { throw ConvexException(code: "UNEXPECTED_OFFLINE_QUERY") }
        return list
    }

    func mutation(_ path: String, _ args: [String: Any]) async throws -> [String: Any] {
        calls.append((path, args))
        return path == "personalTodos:create" ? createAck : [:]
    }
}

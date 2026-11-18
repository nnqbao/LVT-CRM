import Foundation

struct NotificationItem: Identifiable, Equatable, Sendable {
    var id: String { key }
    let key: String
    let kind: String
    let sourceType: String
    let sourceId: String
    let title: String
    let description: String
    let dueAt: Int64
    let milestoneHours: Int
    let milestoneLabel: String
    var read: Bool
    /// Web menu a kind `people` item opens (`staff-faults` / `people-review`); empty otherwise.
    var menu: String = ""
}

struct NotificationSettings: Equatable, Sendable {
    let dutiesEnabled: Bool
    let workEnabled: Bool
    let milestonesHours: [Int]
}

struct NotificationsSnapshot: Equatable, Sendable {
    let items: [NotificationItem]
    let unreadCount: Int
    let canDelete: Bool
    let settings: NotificationSettings
}

enum AppTab: Hashable {
    case overview
    case chat
    case duties
    case work
}

struct NotificationDestination: Equatable, Sendable, Hashable {
    let kind: String
    let sourceType: String
    let sourceId: String
    let notificationKey: String?
    /// Web menu of a kind `people` item (bell feed `menu`); empty when unknown (e.g. an APNs push).
    var menu: String = ""

    var route: AppTab {
        if opensChat { return .chat }
        return kind == "duty" ? .duties : .work
    }

    var chatKind: ChatKind {
        switch sourceType {
        case "duty_chat": return .duty
        case "group_chat": return .group
        default: return .work
        }
    }

    /// "Việc của tôi" reminder (push kind `todo`, bell/push sourceType `todo_reminder`): opens the to-do list
    /// under Công việc, never the work-document focus path.
    var opensTodos: Bool {
        sourceType == PersonalTodos.notificationSourceType || kind == PersonalTodos.notificationKind
    }

    /// Đánh giá nhân sự / Ghi nhận lỗi (kind `people`) have no app screen: they open that web page.
    var opensWeb: Bool { kind == "people" }

    var webPath: String { Self.peopleWebPath(menu: menu, sourceType: sourceType) }

    /// Web route of a `people` item: its feed `menu`, else Ghi nhận lỗi for a fault (mirrors web useNotificationFocus.js).
    static func peopleWebPath(menu: String, sourceType: String) -> String {
        let target = ["staff-faults", "people-review"].contains(menu)
            ? menu
            : (sourceType == "staff_fault" ? "staff-faults" : "people-review")
        return target == "staff-faults" ? "/ghi-nhan-loi" : "/danh-gia-nhan-su"
    }

    /// Bell items for Trao đổi open the chat hub.
    var opensChat: Bool {
        sourceType == "duty_chat" || sourceType == "work_chat" || sourceType == "group_chat"
    }

    static func from(url: URL) -> NotificationDestination? {
        guard url.scheme == "lvtcrm", url.host == "notification" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        guard let sourceId = value("sourceId")?.notificationValue else { return nil }
        return NotificationDestination(
            kind: value("kind") ?? "",
            sourceType: value("sourceType") ?? "",
            sourceId: sourceId,
            notificationKey: value("key")?.notificationValue,
            menu: value("menu") ?? ""
        )
    }

    static func from(userInfo: [AnyHashable: Any]) -> NotificationDestination? {
        let sourceId = (userInfo["sourceId"] as? String)?.notificationValue
            ?? (userInfo["lvt.notification.source_id"] as? String)?.notificationValue
        guard let sourceId else { return nil }
        return NotificationDestination(
            kind: (userInfo["kind"] as? String)
                ?? (userInfo["lvt.notification.kind"] as? String)
                ?? "",
            sourceType: (userInfo["sourceType"] as? String)
                ?? (userInfo["lvt.notification.source_type"] as? String)
                ?? "",
            sourceId: sourceId,
            notificationKey: (userInfo["key"] as? String)?.notificationValue
                ?? (userInfo["lvt.notification.key"] as? String)?.notificationValue,
            menu: (userInfo["menu"] as? String) ?? ""
        )
    }
}

/// Labels of kind `people` items (mirrors web peopleNotificationLabel in src/notifications/useNotificationFocus.js).
enum NotificationPeople {
    static func label(sourceType: String) -> String {
        sourceType == "staff_fault" ? "Ghi nhận lỗi" : "Đánh giá nhân sự"
    }
}

private extension String {
    var notificationValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

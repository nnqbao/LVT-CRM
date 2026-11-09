import Foundation

final class NotificationsRepository: Sendable {
    private let convex: ConvexHttpClient

    init(convex: ConvexHttpClient) {
        self.convex = convex
    }

    func feed(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async throws -> NotificationsSnapshot {
        let result = try await convex.query("notifications:feed", args: ["now": now])
        let array = result["items"] as? [[String: Any]] ?? []
        let items = array.compactMap { item -> NotificationItem? in
            let key = (item["key"] as? String) ?? ""
            let sourceId = (item["sourceId"] as? String) ?? ""
            guard !key.isEmpty, !sourceId.isEmpty else { return nil }
            return NotificationItem(
                key: key,
                kind: (item["kind"] as? String) ?? "",
                sourceType: (item["sourceType"] as? String) ?? "",
                sourceId: sourceId,
                title: (item["title"] as? String) ?? "",
                description: (item["description"] as? String) ?? "",
                dueAt: notificationInt64(item["dueAt"]),
                milestoneHours: notificationInt(item["milestoneHours"]),
                milestoneLabel: (item["milestoneLabel"] as? String) ?? "",
                read: (item["read"] as? Bool) ?? false,
                menu: (item["menu"] as? String) ?? ""
            )
        }
        let settings = result["settings"] as? [String: Any] ?? [:]
        let milestones = (settings["milestonesHours"] as? [Any])?.compactMap { value -> Int? in
            if let int = value as? Int { return int }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        } ?? []
        return NotificationsSnapshot(
            items: items,
            unreadCount: notificationInt(result["unreadCount"], fallback: items.filter { !$0.read }.count),
            canDelete: (result["canDelete"] as? Bool) ?? false,
            settings: NotificationSettings(
                dutiesEnabled: (settings["dutiesEnabled"] as? Bool) ?? true,
                workEnabled: (settings["workEnabled"] as? Bool) ?? true,
                milestonesHours: milestones
            )
        )
    }

    func markRead(notificationKey: String) async throws {
        _ = try await convex.mutation("notifications:markRead", args: ["notificationKey": notificationKey])
    }

    func markAllRead(notificationKeys: [String]) async throws {
        _ = try await convex.mutation(
            "notifications:markAllRead",
            args: ["notificationKeys": notificationKeys]
        )
    }

    func dismiss(notificationKey: String) async throws {
        _ = try await convex.mutation("notifications:dismiss", args: ["notificationKey": notificationKey])
    }
}

private func notificationInt64(_ value: Any?) -> Int64 {
    if let int = value as? Int64 { return int }
    if let int = value as? Int { return Int64(int) }
    if let number = value as? NSNumber { return number.int64Value }
    if let double = value as? Double { return Int64(double) }
    return 0
}

private func notificationInt(_ value: Any?, fallback: Int = 0) -> Int {
    if let int = value as? Int { return int }
    if let number = value as? NSNumber { return number.intValue }
    return fallback
}

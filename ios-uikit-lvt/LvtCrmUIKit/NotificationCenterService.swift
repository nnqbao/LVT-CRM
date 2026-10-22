import Foundation
import UserNotifications

enum NotificationCenterService {
    static let categoryId = "lvt_crm_deadlines"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func show(_ item: NotificationItem) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title(for: item)
        content.body = item.description.isEmpty ? item.title : item.description
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = [
            "kind": item.kind,
            "sourceType": item.sourceType,
            "sourceId": item.sourceId,
            "key": item.key,
        ]
        let request = UNNotificationRequest(identifier: item.key, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    private static func title(for item: NotificationItem) -> String {
        if item.sourceType == "completion_rejected" {
            return "Hoàn thành bị từ chối"
        }
        if item.sourceType == "duty_chat" || item.sourceType == "work_chat" || item.sourceType == "group_chat" {
            return "Trao đổi"
        }
        if item.kind == "work", let label = WorkApprovalRules.notificationLabel(sourceType: item.sourceType) {
            return label
        }
        if !item.milestoneLabel.isEmpty {
            return item.milestoneLabel
        }
        return item.title
    }
}

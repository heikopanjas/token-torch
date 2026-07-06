import UserNotifications

@MainActor
enum NotificationService {
    /// First launch: request access when undetermined; on grant, post the welcome notification.
    static func bootstrap() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            if (try? await center.requestAuthorization(options: [.alert, .sound])) == true {
                Self.post(.welcome)
            }
        }
    }

    static func post(_ notification: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        if notification.playsSound == true {
            content.sound = .default
        }
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

import UserNotifications

@MainActor
enum NotificationService {
    /// First launch: request access when undetermined; on grant, post the welcome notification.
    static func bootstrap() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                Task { @MainActor in post(.welcome) }
            }
        }
    }

    static func post(_ notification: AppNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        if notification.playsSound {
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

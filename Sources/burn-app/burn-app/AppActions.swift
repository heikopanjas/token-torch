import AppKit
import Foundation

enum AppActions {
    static let openSettingsNotification = Notification.Name("burn.openSettings")
    static let burnRefreshRequested = Notification.Name("burn.refreshRequested")

    static func requestOpenSettings() {
        NotificationCenter.default.post(name: openSettingsNotification, object: nil)
    }

    static func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension AppActions {
    static func activateForSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func deactivateAfterSettings() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

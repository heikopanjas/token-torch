import AppKit
import Foundation

enum AppActions {
    static let openSettingsNotification = Notification.Name("tokentorch.openSettings")
    static let tokenTorchRefreshRequested = Notification.Name("tokentorch.refreshRequested")
    /// Posted when a display-only preference (e.g. currency) changes; rebuilds the menu without refetching.
    static let tokenTorchDisplayChanged = Notification.Name("tokentorch.displayChanged")

    static func requestOpenSettings() {
        NotificationCenter.default.post(name: openSettingsNotification, object: nil)
    }

    @MainActor
    static func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
extension AppActions {
    static func activateForSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func deactivateAfterSettings() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

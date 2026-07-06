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
    /// Settings window tracked so About close does not hide the Dock while Settings stays open.
    static weak var settingsWindow: NSWindow?

    private static var aboutPanelTracker: AboutPanelLifecycleTracker?

    static func activateForSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    static func deactivateAfterSettings() {
        Self.restoreAccessoryActivationIfNeeded()
    }

    static func showAbout() {
        Self.activateForSettings()
        let windowsBeforeShow = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
        Self.locateAboutPanel(excluding: windowsBeforeShow, attempt: 0)
    }

    static func restoreAccessoryActivationIfNeeded() {
        guard Self.hasVisibleUserPanel == false else { return }
        NSApplication.shared.hide(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private static var hasVisibleUserPanel: Bool {
        if Self.settingsWindow?.isVisible == true { return true }
        guard Self.aboutPanelTracker != nil else { return false }
        return NSApplication.shared.windows.contains { window in
            window.isVisible && Self.looksLikeAboutPanel(window)
        }
    }

    private static func looksLikeAboutPanel(_ window: NSWindow) -> Bool {
        let className = String(describing: type(of: window))
        if className.localizedCaseInsensitiveContains("About") {
            return true
        }
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else { return false }
        guard title.localizedCaseInsensitiveContains(AppBrand.displayName) else { return false }
        let lower = title.lowercased()
        return lower.contains("about") || lower.contains("über") || lower.contains("ueber")
    }

    private static func locateAboutPanel(excluding windowsBeforeShow: Set<ObjectIdentifier>, attempt: Int) {
        Task { @MainActor in
            if let aboutWindow = Self.findAboutPanelWindow(excluding: windowsBeforeShow) {
                Self.attachAboutPanelTracker(to: aboutWindow)
                return
            }
            guard attempt < 10 else { return }
            try? await Task.sleep(for: .milliseconds(50))
            Self.locateAboutPanel(excluding: windowsBeforeShow, attempt: attempt + 1)
        }
    }

    private static func findAboutPanelWindow(excluding windowsBeforeShow: Set<ObjectIdentifier>) -> NSWindow? {
        let app = NSApplication.shared
        if let newWindow = app.windows.first(where: { window in
            windowsBeforeShow.contains(ObjectIdentifier(window)) == false
                && window.isVisible
                && window !== Self.settingsWindow
        }) {
            return newWindow
        }
        if let keyWindow = app.keyWindow,
            keyWindow.isVisible,
            keyWindow !== Self.settingsWindow,
            windowsBeforeShow.contains(ObjectIdentifier(keyWindow)) == false
        {
            return keyWindow
        }
        return app.windows.first { window in
            window.isVisible
                && window !== Self.settingsWindow
                && Self.looksLikeAboutPanel(window)
        }
    }

    private static func attachAboutPanelTracker(to window: NSWindow) {
        Self.aboutPanelTracker?.stop()
        let tracker = AboutPanelLifecycleTracker {
            Self.aboutPanelTracker = nil
            Self.restoreAccessoryActivationIfNeeded()
        }
        tracker.track(window)
        Self.aboutPanelTracker = tracker
    }
}

@MainActor
private final class AboutPanelLifecycleTracker {
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func track(_ window: NSWindow) {
        self.window = window
        let names: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didResignKeyNotification
        ]
        for name in names {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self] notification in
                    let notificationName = notification.name
                    MainActor.assumeIsolated {
                        self?.handleWindowChanged(notificationName: notificationName)
                    }
                }
            )
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        window = nil
    }

    private func handleWindowChanged(notificationName: Notification.Name) {
        if notificationName == NSWindow.willCloseNotification {
            self.finish()
            return
        }
        guard let window = self.window else {
            self.finish()
            return
        }
        if window.isVisible == false {
            self.finish()
        }
    }

    private func finish() {
        self.stop()
        self.onDismiss()
    }
}

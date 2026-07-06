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
        restoreAccessoryActivationIfNeeded()
    }

    static func showAbout() {
        activateForSettings()
        let windowsBeforeShow = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
        locateAboutPanel(excluding: windowsBeforeShow, attempt: 0)
    }

    static func restoreAccessoryActivationIfNeeded() {
        guard !hasVisibleUserPanel else { return }
        NSApplication.shared.hide(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private static var hasVisibleUserPanel: Bool {
        NSApplication.shared.windows.contains { window in
            window.isVisible && isUserPanel(window)
        }
    }

    private static func isUserPanel(_ window: NSWindow) -> Bool {
        window === settingsWindow || looksLikeAboutPanel(window)
    }

    private static func looksLikeAboutPanel(_ window: NSWindow) -> Bool {
        let className = String(describing: type(of: window))
        if className.localizedCaseInsensitiveContains("About") {
            return true
        }
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        guard title.localizedCaseInsensitiveContains(AppBrand.displayName) else { return false }
        let lower = title.lowercased()
        return lower.contains("about") || lower.contains("über") || lower.contains("ueber")
    }

    private static func locateAboutPanel(excluding windowsBeforeShow: Set<ObjectIdentifier>, attempt: Int) {
        DispatchQueue.main.async {
            if let aboutWindow = findAboutPanelWindow(excluding: windowsBeforeShow) {
                attachAboutPanelTracker(to: aboutWindow)
                return
            }
            guard attempt < 10 else { return }
            locateAboutPanel(excluding: windowsBeforeShow, attempt: attempt + 1)
        }
    }

    private static func findAboutPanelWindow(excluding windowsBeforeShow: Set<ObjectIdentifier>) -> NSWindow? {
        let app = NSApplication.shared
        if let newWindow = app.windows.first(where: { window in
            !windowsBeforeShow.contains(ObjectIdentifier(window))
                && window.isVisible
                && window !== settingsWindow
        }) {
            return newWindow
        }
        if let keyWindow = app.keyWindow, keyWindow.isVisible, keyWindow !== settingsWindow {
            return keyWindow
        }
        return app.windows.first { window in
            window.isVisible && window !== settingsWindow && looksLikeAboutPanel(window)
        }
    }

    private static func attachAboutPanelTracker(to window: NSWindow) {
        aboutPanelTracker?.stop()
        let tracker = AboutPanelLifecycleTracker {
            aboutPanelTracker = nil
            restoreAccessoryActivationIfNeeded()
        }
        tracker.track(window)
        aboutPanelTracker = tracker
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
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.handleWindowChanged()
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

    private func handleWindowChanged() {
        guard let window else {
            finish()
            return
        }
        if !window.isVisible {
            finish()
        }
    }

    private func finish() {
        stop()
        onDismiss()
    }
}

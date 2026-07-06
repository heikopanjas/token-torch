import ServiceManagement

/// Registers Token Torch as a login item via `SMAppService` (macOS 13+).
enum LoginItemRegistration {
    /// True when the app is registered to launch at login, including when macOS
    /// still requires approval in System Settings.
    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval: true
            default: false
        }
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled == true {
            try SMAppService.mainApp.register()
        }
        else {
            try SMAppService.mainApp.unregister()
        }
    }
}

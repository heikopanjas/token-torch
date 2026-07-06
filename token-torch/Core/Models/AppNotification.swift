import Foundation

public struct AppNotification: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let body: String
    public let playsSound: Bool

    public init(identifier: String, title: String, body: String, playsSound: Bool = true) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.playsSound = playsSound
    }
}

extension AppNotification {
    public static let welcome = AppNotification(
        identifier: "token-torch.welcome",
        title: "\(AppBrand.displayName) notifications enabled",
        body: "You'll be alerted about issues like failed Claude Code credential repair.",
        playsSound: false
    )

    public static func claudeRepairFailed(message: String) -> AppNotification {
        AppNotification(
            identifier: "token-torch.claude-repair-failed",
            title: "Claude Code credential repair failed",
            body: message
        )
    }
}

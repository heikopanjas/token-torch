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
        body: "You'll be alerted about issues like failed Claude Code credential repair, and when a usage limit runs high.",
        playsSound: false
    )

    public static func claudeRepairFailed(message: String) -> AppNotification {
        AppNotification(
            identifier: "token-torch.claude-repair-failed",
            title: "Claude Code credential repair failed",
            body: message
        )
    }

    /// One banner per provider section; the identifier is stable per section so a later escalation
    /// replaces the earlier banner instead of stacking a second one.
    public static func usageThresholdReached(section: ProviderSection, rows: [CappedUsageRow]) -> AppNotification {
        let highestLevel = rows.map(\.level).max() ?? .low
        let title = "\(section.heading): \(highestLevel.alertDisplayName) usage"
        let body =
            rows
            .map { "\($0.label) at \(QuotaHelpers.formattedPercent($0.usedPercent))" }
            .joined(separator: "\n")
        return AppNotification(
            identifier: "token-torch.usage-threshold.\(section.id)",
            title: title,
            body: body
        )
    }
}

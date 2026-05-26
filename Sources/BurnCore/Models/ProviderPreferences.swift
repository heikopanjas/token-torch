import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude
    case codex
    case cursor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .claude: "Claude"
            case .codex: "Codex"
            case .cursor: "Cursor"
        }
    }

    public var supportsOrgBilling: Bool {
        switch self {
            case .claude, .codex: true
            case .cursor: false
        }
    }
}

public struct ProviderModeFlags: Codable, Sendable, Equatable {
    public var subscriptionQuotaEnabled: Bool
    public var orgBillingEnabled: Bool

    public init(subscriptionQuotaEnabled: Bool = true, orgBillingEnabled: Bool = false) {
        self.subscriptionQuotaEnabled = subscriptionQuotaEnabled
        self.orgBillingEnabled = orgBillingEnabled
    }
}

public struct ProviderPreferences: Codable, Sendable, Equatable {
    public var claude: ProviderModeFlags
    public var codex: ProviderModeFlags
    public var cursor: ProviderModeFlags
    public var refreshIntervalMinutes: Int

    public init(
        claude: ProviderModeFlags = .init(),
        codex: ProviderModeFlags = .init(),
        cursor: ProviderModeFlags = .init(subscriptionQuotaEnabled: true, orgBillingEnabled: false),
        refreshIntervalMinutes: Int = 15
    ) {
        self.claude = claude
        self.codex = codex
        self.cursor = cursor
        self.refreshIntervalMinutes = refreshIntervalMinutes
    }

    public func flags(for provider: ProviderID) -> ProviderModeFlags {
        switch provider {
            case .claude: claude
            case .codex: codex
            case .cursor: cursor
        }
    }

    public mutating func setFlags(_ flags: ProviderModeFlags, for provider: ProviderID) {
        switch provider {
            case .claude: claude = flags
            case .codex: codex = flags
            case .cursor: cursor = flags
        }
    }
}

public enum AppKeyKind: String, Sendable {
    case apiKey
    case adminKey

    public func service(for provider: ProviderID) -> String {
        "com.burn.keys.\(provider.rawValue).\(rawValue)"
    }
}

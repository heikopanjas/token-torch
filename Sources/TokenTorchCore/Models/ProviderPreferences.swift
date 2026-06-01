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

public enum ProviderSectionKind: String, Codable, CaseIterable, Sendable {
    case subscription
    case orgBilling
}

/// One reorderable menu "view": a provider paired with the kind of report it shows
/// (subscription quota or org billing). Five are valid: Claude, Anthropic API, ChatGPT,
/// OpenAI Platform, Cursor (Cursor has no org billing).
public struct ProviderSection: Codable, Hashable, Sendable, Identifiable {
    public let provider: ProviderID
    public let kind: ProviderSectionKind

    public init(provider: ProviderID, kind: ProviderSectionKind) {
        self.provider = provider
        self.kind = kind
    }

    public var id: String { "\(provider.rawValue).\(kind.rawValue)" }

    /// Every valid menu view, grouped by provider (subscription then org billing).
    public static var allSections: [ProviderSection] {
        ProviderID.allCases.flatMap { provider -> [ProviderSection] in
            var sections = [ProviderSection(provider: provider, kind: .subscription)]
            if provider.supportsOrgBilling {
                sections.append(ProviderSection(provider: provider, kind: .orgBilling))
            }
            return sections
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
    public var displayCurrency: DisplayCurrency
    /// When true, the menu also lists per-model extra rate limits (e.g. Codex Spark). Default off.
    public var showAdditionalModelUsage: Bool
    /// User-chosen order of the five menu views (provider + subscription/org). Normalize via `orderedSections()`.
    public var sectionOrder: [ProviderSection]

    public init(
        claude: ProviderModeFlags = .init(),
        codex: ProviderModeFlags = .init(),
        cursor: ProviderModeFlags = .init(subscriptionQuotaEnabled: true, orgBillingEnabled: false),
        refreshIntervalMinutes: Int = 15,
        displayCurrency: DisplayCurrency = .systemDefault,
        showAdditionalModelUsage: Bool = false,
        sectionOrder: [ProviderSection] = ProviderSection.allSections
    ) {
        self.claude = claude
        self.codex = codex
        self.cursor = cursor
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.displayCurrency = displayCurrency
        self.showAdditionalModelUsage = showAdditionalModelUsage
        self.sectionOrder = sectionOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claude = try container.decodeIfPresent(ProviderModeFlags.self, forKey: .claude) ?? .init()
        codex = try container.decodeIfPresent(ProviderModeFlags.self, forKey: .codex) ?? .init()
        cursor =
            try container.decodeIfPresent(ProviderModeFlags.self, forKey: .cursor)
            ?? .init(subscriptionQuotaEnabled: true, orgBillingEnabled: false)
        refreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) ?? 15
        displayCurrency = try container.decodeIfPresent(DisplayCurrency.self, forKey: .displayCurrency) ?? .systemDefault
        showAdditionalModelUsage = try container.decodeIfPresent(Bool.self, forKey: .showAdditionalModelUsage) ?? false
        sectionOrder = try container.decodeIfPresent([ProviderSection].self, forKey: .sectionOrder) ?? ProviderSection.allSections
    }

    /// True when at least one provider has subscription quota or org billing enabled.
    public var hasAnyEnabledProvider: Bool {
        ProviderID.allCases.contains { provider in
            let flags = flags(for: provider)
            return flags.subscriptionQuotaEnabled || flags.orgBillingEnabled
        }
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

    /// The menu-view display order, normalized: unknown/invalid sections dropped, any valid section
    /// missing from the stored order appended in `ProviderSection.allSections` order (so new views appear).
    public func orderedSections() -> [ProviderSection] {
        let valid = ProviderSection.allSections
        let known = sectionOrder.filter { valid.contains($0) }
        let missing = valid.filter { !known.contains($0) }
        return known + missing
    }

    public mutating func setSectionOrder(_ order: [ProviderSection]) {
        sectionOrder = order
    }

    /// Whether the menu view (provider + subscription/org) is enabled, read from its `ProviderModeFlags` bit.
    public func isSectionEnabled(_ section: ProviderSection) -> Bool {
        let modeFlags = flags(for: section.provider)
        return section.kind == .subscription ? modeFlags.subscriptionQuotaEnabled : modeFlags.orgBillingEnabled
    }

    public mutating func setSection(_ section: ProviderSection, enabled: Bool) {
        var modeFlags = flags(for: section.provider)
        if section.kind == .subscription {
            modeFlags.subscriptionQuotaEnabled = enabled
        }
        else {
            modeFlags.orgBillingEnabled = enabled
        }
        setFlags(modeFlags, for: section.provider)
    }

    /// Sort position of a menu view in the user-chosen order (used to order the menu sections).
    public func sectionOrderIndex(of section: ProviderSection) -> Int {
        orderedSections().firstIndex(of: section) ?? Int.max
    }

    /// Sort position of a provider, taken from the earliest of its sections in the user order.
    /// Used to order `UsageOrchestrator` fetch results (which are grouped per provider).
    public func providerOrderIndex(of provider: ProviderID) -> Int {
        orderedSections().firstIndex { $0.provider == provider } ?? Int.max
    }
}

public enum AppKeyKind: String, Sendable {
    case apiKey
    case adminKey

    public func service(for provider: ProviderID) -> String {
        "com.tokentorch.keys.\(provider.rawValue).\(rawValue)"
    }
}

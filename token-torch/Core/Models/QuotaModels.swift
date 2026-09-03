import Foundation

public struct QuotaWindow: Codable, Sendable, Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    /// Copilot `/copilot_internal/user` quota snapshot fields (nil for other providers).
    public let entitlement: Int?
    public let remaining: Int?
    public let quotaRemaining: Double?
    public let percentRemaining: Double?
    public let overageCount: Int?
    public let overagePermitted: Bool?

    public init(
        label: String,
        usedPercent: Double,
        resetsAt: Date?,
        entitlement: Int? = nil,
        remaining: Int? = nil,
        quotaRemaining: Double? = nil,
        percentRemaining: Double? = nil,
        overageCount: Int? = nil,
        overagePermitted: Bool? = nil
    ) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.entitlement = entitlement
        self.remaining = remaining
        self.quotaRemaining = quotaRemaining
        self.percentRemaining = percentRemaining
        self.overageCount = overageCount
        self.overagePermitted = overagePermitted
    }
}

extension QuotaWindow {
    /// The percentage this row actually states. Copilot carries a group's percentage as
    /// `percentRemaining` rather than `usedPercent`; every other provider leaves `percentRemaining`
    /// nil, so this collapses to `usedPercent`. Single source for the row's printed text, its usage
    /// bar, and usage-threshold alerts — they can never disagree.
    public var cappedUsedPercent: Double {
        percentRemaining.map { 100 - $0 } ?? usedPercent
    }
}

/// A single labeled scalar/flag value surfaced from a provider response that doesn't fit the
/// window or money layouts (e.g. ChatGPT `allowed`, `spend_control`).
public struct QuotaNote: Codable, Sendable, Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct CreditsInfo: Codable, Sendable, Equatable {
    /// Sentinel `currency` for non-monetary AI credit counts (GitHub Copilot).
    public static let creditUnitsCurrency = "CREDITS"

    public let usedCents: UInt64
    public let limitCents: UInt64
    public let currency: String
    public let balanceUSD: Double?
    /// Provider-supplied remaining credit balance when the value is a count, not money.
    public let balanceCredits: Double?
    /// Server-provided utilization percentage, when available (preferred over a recomputed value).
    public let utilizationPercent: Double?

    public init(
        usedCents: UInt64,
        limitCents: UInt64,
        currency: String,
        balanceUSD: Double?,
        balanceCredits: Double? = nil,
        utilizationPercent: Double? = nil
    ) {
        self.usedCents = usedCents
        self.limitCents = limitCents
        self.currency = currency
        self.balanceUSD = balanceUSD
        self.balanceCredits = balanceCredits
        self.utilizationPercent = utilizationPercent
    }
}

extension CreditsInfo {
    /// The share of the cap actually spent, preferring the server-supplied percentage and falling
    /// back to a recomputation from cents. nil when there is no cap to be a share of.
    private var resolvedUsedPercent: Double? {
        utilizationPercent ?? QuotaHelpers.creditUsedPercent(usedCents: usedCents, limitCents: limitCents)
    }

    /// The percentage a credits row's usage bar should show, or nil when the row states a balance
    /// (e.g. Codex `extra_usage`) rather than a share of a cap. Single source for the row's printed
    /// text, its usage bar, and usage-threshold alerts.
    public var cappedUsedPercent: Double? {
        if currency != CreditsInfo.creditUnitsCurrency, balanceUSD != nil { return nil }
        guard limitCents > 0 else { return nil }
        return resolvedUsedPercent
    }
}

public struct DollarUsage: Codable, Sendable, Equatable {
    public let usedCents: UInt64
    public let limitCents: UInt64
    public let remainingCents: UInt64
    public let usedPercent: Double?

    public init(usedCents: UInt64, limitCents: UInt64, remainingCents: UInt64, usedPercent: Double?) {
        self.usedCents = usedCents
        self.limitCents = limitCents
        self.remainingCents = remainingCents
        self.usedPercent = usedPercent
    }
}

extension DollarUsage {
    /// The share of the cap actually spent, preferring the server-supplied percentage and falling
    /// back to a recomputation from cents. nil when there is no cap to be a share of.
    public var resolvedUsedPercent: Double? {
        usedPercent ?? QuotaHelpers.creditUsedPercent(usedCents: usedCents, limitCents: limitCents)
    }
}

public struct SubscriptionQuotaReport: Codable, Sendable, Equatable {
    public let provider: String
    public var planTier: String?
    public var windows: [QuotaWindow]
    /// Per-model extra rate-limit windows (e.g. ChatGPT `additional_rate_limits` like Codex Spark).
    /// Kept separate so the UI can hide them behind an opt-in setting.
    public var additionalWindows: [QuotaWindow]
    public var notes: [QuotaNote]
    public var credits: CreditsInfo?
    public var dollarUsage: DollarUsage?
    public var billingCycleStart: Date?
    public var billingCycleEnd: Date?
    public var planPrice: String?
    public var includedAllowanceCents: UInt64?
    public var apiAllowance: DollarUsage?
    public var periodSpendCents: UInt64?
    public var totalSpendCents: UInt64?
    public var bonusSpendCents: UInt64?
    public var rawMessage: String?

    public init(provider: String) {
        self.provider = provider
        self.planTier = nil
        self.windows = []
        self.additionalWindows = []
        self.notes = []
        self.credits = nil
        self.dollarUsage = nil
        self.billingCycleStart = nil
        self.billingCycleEnd = nil
        self.planPrice = nil
        self.includedAllowanceCents = nil
        self.apiAllowance = nil
        self.periodSpendCents = nil
        self.totalSpendCents = nil
        self.bonusSpendCents = nil
        self.rawMessage = nil
    }

    public static func forProvider(_ provider: String) -> SubscriptionQuotaReport {
        SubscriptionQuotaReport(provider: provider)
    }
}

extension SubscriptionQuotaReport {
    /// Share of the included allowance Cursor has spent, i.e. the percentage its credits row prints.
    /// Single source for the row's text, its usage bar, and usage-threshold alerts.
    public var cursorCreditsPercent: Double? {
        guard let usage = apiAllowance ?? dollarUsage, usage.limitCents > 0 else { return nil }
        return usage.resolvedUsedPercent
    }

    /// The percentage a non-Cursor credits row's usage bar should show, or nil when the row states a
    /// balance rather than a share of a cap (e.g. Codex `extra_usage`, whose `limitCents` is always 0).
    public var creditsRowPercent: Double? {
        credits?.cappedUsedPercent
    }
}

/// Window labels the menu has to recognize for opt-in gating, kept in one place so the provider that
/// produces the row and the menu that hides it cannot drift apart.
public enum QuotaWindowLabel {
    /// Claude's model-scoped weekly Fable sub-cap; hidden unless `ProviderPreferences.showClaudeFableUsage` is on.
    public static let claudeFableShare = "Fable share of 7-day limit"
    /// Cursor's three non-additive meters, in menu order. Single source for the menu's row selection
    /// and the usage-threshold alert scan — both must agree on exactly which windows are meters.
    public static let cursorMeters = ["Included total usage", "Auto + Composer", "Included API usage"]
}

/// Severity band of a usage percentage, driving the color of the menu's usage bar and, from
/// `ProviderPreferences.usageAlertStartLevel` upward, desktop usage-threshold alerts.
public enum UsageLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case low
    case moderate
    case high
    case severe
    case critical

    /// Inclusive lower bound of the band. `level(forPercent:)`, the Settings "Starting at" popup, and
    /// the alert copy all derive from this, so the band edges are written exactly once.
    public var thresholdPercent: Double {
        switch self {
            case .low: return 0
            case .moderate: return 50
            case .high: return 75
            case .severe: return 87
            case .critical: return 95
        }
    }

    /// Band name used in the Settings popup and alert copy ("Orange", "Red", …).
    public var alertDisplayName: String {
        switch self {
            case .low: return "Green"
            case .moderate: return "Green"
            case .high: return "Orange"
            case .severe: return "Red"
            case .critical: return "Deep red"
        }
    }

    /// Declaration order, `low` lowest. Not derived from `thresholdPercent` so the ordering survives
    /// even if a future band's threshold were ever revisited.
    private var rank: Int {
        switch self {
            case .low: return 0
            case .moderate: return 1
            case .high: return 2
            case .severe: return 3
            case .critical: return 4
        }
    }

    public static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Bands are exclusive upper bounds, so exactly 50% is already `.moderate` and exactly 95%
    /// is already `.critical`.
    public static func level(forPercent percent: Double) -> UsageLevel {
        Self.allCases.reversed().first { percent >= $0.thresholdPercent } ?? .low
    }
}

public enum UsageBarMetrics {
    /// Below this the row carries no bar at all: a track with no perceptible fill is noise, not
    /// information, and an untouched pool reads better bare.
    public static let minimumVisiblePercent: Double = 1

    public static func showsBar(forPercent percent: Double) -> Bool {
        percent >= Self.minimumVisiblePercent
    }

    /// Usage as a 0...1 fill fraction. Providers can report past their cap (Copilot overage counts
    /// beyond 100%), so the fraction is clamped rather than trusted.
    public static func fillFraction(forPercent percent: Double) -> Double {
        min(max(percent, 0) / 100, 1)
    }
}

public enum QuotaHelpers {
    public static func pushWindow(
        _ windows: inout [QuotaWindow],
        label: String,
        usedPercent: Double,
        resetsAt: Date?,
        skipIfEmpty: Bool
    ) {
        if skipIfEmpty, resetsAt == nil, usedPercent == 0 { return }
        windows.append(QuotaWindow(label: label, usedPercent: usedPercent, resetsAt: resetsAt))
    }

    public static func parseRFC3339UTC(_ value: String) -> Date? {
        // Some providers (e.g. Claude `resets_at`) include fractional seconds; try that first.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        // Claude emits microsecond precision (6 digits) that ISO8601DateFormatter rejects; strip it.
        return formatter.date(from: stripFractionalSeconds(value))
    }

    private static func stripFractionalSeconds(_ value: String) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        var end = value.index(after: dot)
        while end < value.endIndex, value[end].isNumber { end = value.index(after: end) }
        var result = value
        result.removeSubrange(dot ..< end)
        return result
    }

    public static func parseUnixSecsUTC(_ secs: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(secs))
    }

    public static func parseUnixMillisStrUTC(_ value: String) -> Date? {
        guard let millis = Int64(value) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
    }

    public static func centsToDollars(_ cents: UInt64) -> Double {
        Double(cents) / 100.0
    }

    public static func dollarUsageFromPercent(limitCents: UInt64, usedPercent: Double) -> DollarUsage {
        let used = UInt64((Double(limitCents) * usedPercent / 100.0).rounded())
        return DollarUsage(
            usedCents: used,
            limitCents: limitCents,
            remainingCents: limitCents >= used ? limitCents - used : 0,
            usedPercent: usedPercent
        )
    }

    public static func creditUsedPercent(usedCents: UInt64, limitCents: UInt64) -> Double? {
        guard limitCents > 0 else { return nil }
        return Double(usedCents) / Double(limitCents) * 100.0
    }

    /// "NN%", rounded the same way everywhere a percentage is printed — the menu row, its usage bar's
    /// implicit value, and a usage-threshold alert all read the identical number.
    public static func formattedPercent(_ percent: Double) -> String {
        String(format: "%.0f%%", percent)
    }
}

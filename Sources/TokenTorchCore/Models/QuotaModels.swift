import Foundation

public struct QuotaWindow: Codable, Sendable, Equatable, Identifiable {
    public var id: String { label }
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
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
    public let usedCents: UInt64
    public let limitCents: UInt64
    public let currency: String
    public let balanceUSD: Double?
    /// Server-provided utilization percentage, when available (preferred over a recomputed value).
    public let utilizationPercent: Double?

    public init(
        usedCents: UInt64,
        limitCents: UInt64,
        currency: String,
        balanceUSD: Double?,
        utilizationPercent: Double? = nil
    ) {
        self.usedCents = usedCents
        self.limitCents = limitCents
        self.currency = currency
        self.balanceUSD = balanceUSD
        self.utilizationPercent = utilizationPercent
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
}

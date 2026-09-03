import Foundation

/// Stable identity of a row that states a share of a cap, used to track which usage band it last
/// alerted at. Deliberately carries no percentage and no `resetsAt` — both rotate every window and
/// would churn the key into permanent re-notification.
public struct UsageAlertRowKey: Hashable, Sendable {
    public enum Source: String, Sendable {
        case window
        case credits
    }

    public let section: ProviderSection
    public let source: Source
    public let label: String
    /// 0 for the first row with this `(source, label)` in a report; disambiguates duplicates that
    /// would otherwise collide deterministically (e.g. two Codex additional limits with no
    /// `limit_name`, both falling back to the same generated label).
    public let occurrence: Int

    public init(section: ProviderSection, source: Source, label: String, occurrence: Int = 0) {
        self.section = section
        self.source = source
        self.label = label
        self.occurrence = occurrence
    }

    /// Flat string form used as the UserDefaults-backed state dictionary's key.
    public var storageKey: String {
        let base = "\(section.id).\(source.rawValue).\(label)"
        return occurrence == 0 ? base : "\(base)#\(occurrence)"
    }
}

/// One row that states a share of a cap, ready for band comparison. Mirrors exactly the rows the
/// menu attaches a usage bar to (see `UsageBarMetrics`).
public struct CappedUsageRow: Sendable, Equatable {
    public let key: UsageAlertRowKey
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public var level: UsageLevel { .level(forPercent: usedPercent) }

    public init(key: UsageAlertRowKey, label: String, usedPercent: Double, resetsAt: Date?) {
        self.key = key
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Enumerates every row of a fetch result that states a share of a cap, after the same display-only
/// gating the menu applies. Single source for usage-threshold alerts: it reuses
/// `ProviderPreferences.visibleWindows`, `QuotaWindow.cappedUsedPercent`, and
/// `SubscriptionQuotaReport.creditsRowPercent` / `.cursorCreditsPercent` — the exact values the menu
/// prints and bars — rather than re-deriving them.
public enum CappedUsageRows {
    public static func rows(
        provider: ProviderID,
        quota: SubscriptionQuotaReport,
        preferences: ProviderPreferences
    ) -> [CappedUsageRow] {
        let section = ProviderSection(provider: provider, kind: .subscription)
        var occurrences: [String: Int] = [:]
        func nextOccurrence(_ label: String) -> Int {
            let n = occurrences[label, default: 0]
            occurrences[label] = n + 1
            return n
        }

        var rows = preferences.visibleWindows(provider: provider, quota: quota).map { window in
            CappedUsageRow(
                key: UsageAlertRowKey(
                    section: section,
                    source: .window,
                    label: window.label,
                    occurrence: nextOccurrence(window.label)
                ),
                label: window.label,
                usedPercent: window.cappedUsedPercent,
                resetsAt: window.resetsAt
            )
        }

        let creditsPercent = provider == .cursor ? quota.cursorCreditsPercent : quota.creditsRowPercent
        if let creditsPercent {
            let label = ReportLabels.creditsTitle(for: quota.provider)
            rows.append(
                CappedUsageRow(
                    key: UsageAlertRowKey(section: section, source: .credits, label: label),
                    label: label,
                    usedPercent: creditsPercent,
                    resetsAt: quota.billingCycleEnd
                ))
        }
        return rows
    }

    /// Every capped row across every enabled subscription section of a fetch result.
    public static func rows(in result: AllProvidersResult, preferences: ProviderPreferences) -> [CappedUsageRow] {
        result.results.flatMap { providerResult -> [CappedUsageRow] in
            guard preferences.isSectionEnabled(ProviderSection(provider: providerResult.provider, kind: .subscription))
            else { return [] }
            return providerResult.reports.flatMap { report -> [CappedUsageRow] in
                guard case .subscription(let quota) = report else { return [] }
                return Self.rows(provider: providerResult.provider, quota: quota, preferences: preferences)
            }
        }
    }

    /// Subscription sections that returned a usable `.subscription` report this refresh. Alert state
    /// is pruned only within these, so a transient `.error` / `.needsAuthorization` never re-arms an
    /// alert for a row the fetch simply didn't reach this time.
    public static func reportingSections(in result: AllProvidersResult, preferences: ProviderPreferences) -> Set<ProviderSection> {
        var sections: Set<ProviderSection> = []
        for providerResult in result.results {
            let section = ProviderSection(provider: providerResult.provider, kind: .subscription)
            guard preferences.isSectionEnabled(section) else { continue }
            if providerResult.reports.contains(where: { if case .subscription = $0 { return true } else { return false } }) {
                sections.insert(section)
            }
        }
        return sections
    }
}

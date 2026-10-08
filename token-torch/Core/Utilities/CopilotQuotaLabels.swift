import Foundation

/// Display formatting for GitHub Copilot `quota_snapshots` rows mapped into `QuotaWindow`.
public enum CopilotQuotaLabels {
    /// Window labels for the quota groups, rendered like Claude's and Codex's window rows (percent, reset
    /// caption, usage bar). The `premium_interactions` group counts AI credits; the free-tier chat and
    /// completions groups count messages and completions, so only the monthly window's amounts carry a
    /// "credits" unit.
    public static let monthlyWindowLabel = "Monthly window"
    public static let chatWindowLabel = "Chat (monthly)"
    public static let completionsWindowLabel = "Completions (monthly)"

    /// Detail rows under a group's window row, in units rather than percent (`20000 credits`, `667 credits`).
    public static func metricItems(_ window: QuotaWindow) -> [QuotaNote] {
        var rows: [QuotaNote] = []
        if let entitlement = window.entitlement {
            rows.append(QuotaNote(label: "Entitlement", value: Self.amount(entitlement, in: window)))
        }
        if let used = Self.usedAmount(window) {
            rows.append(QuotaNote(label: "Usage", value: Self.amount(used, in: window)))
        }
        return rows
    }

    /// Boolean policy row, styled like Claude `Extra usage` (`enabled` / `disabled`).
    public static func overagePermittedNote(_ window: QuotaWindow) -> QuotaNote? {
        guard let permitted = window.overagePermitted else { return nil }
        return QuotaNote(label: "Overage", value: permitted ? "enabled" : "disabled")
    }

    /// Cap on overage beyond the included credits; only meaningful while overage is enabled.
    public static func overageLimitNote(_ window: QuotaWindow) -> QuotaNote? {
        guard window.overagePermitted == true else { return nil }
        guard let overageEntitlement = window.overageEntitlement, overageEntitlement > 0 else { return nil }
        return QuotaNote(label: "Overage limit", value: Self.amount(overageEntitlement, in: window))
    }

    /// Usage beyond the included amount, named to pair with "Overage limit" (`500 credits`).
    public static func overageUsedNote(_ window: QuotaWindow) -> QuotaNote? {
        guard let overageCount = window.overageCount, overageCount > 0 else { return nil }
        return QuotaNote(label: "Overage used", value: Self.amount(overageCount, in: window))
    }

    /// All rows for one quota group, in display order.
    public static func displayItems(_ window: QuotaWindow) -> [QuotaNote] {
        var rows = metricItems(window)
        if let note = overagePermittedNote(window) { rows.append(note) }
        if let note = overageLimitNote(window) { rows.append(note) }
        if let note = overageUsedNote(window) { rows.append(note) }
        return rows
    }

    /// Exact when `remaining` is reported, otherwise derived from the percentage remaining.
    private static func usedAmount(_ window: QuotaWindow) -> Int? {
        guard let entitlement = window.entitlement else { return nil }
        if let remaining = window.remaining {
            return max(0, entitlement - remaining)
        }
        guard let percentRemaining = window.percentRemaining else { return nil }
        return Int((Double(entitlement) * (100 - percentRemaining) / 100).rounded())
    }

    /// `20000 credits` for the monthly window, a bare count for the free-tier chat / completions windows.
    private static func amount(_ count: Int, in window: QuotaWindow) -> String {
        return (window.label == Self.monthlyWindowLabel) ? "\(count) credits" : String(count)
    }
}

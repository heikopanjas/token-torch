import Foundation

/// Display formatting for GitHub Copilot `quota_snapshots` rows mapped into `QuotaWindow`.
public enum CopilotQuotaLabels {
    /// The percentage row of a quota group. Shared so the menu can attach the usage bar to that row
    /// without matching a repeated literal — the percent itself lives on the group's `QuotaWindow`.
    public static let percentUsedLabel = "Usage"

    /// The `premium_interactions` group. Its counts are AI credits; the free-tier Chat and Completions
    /// groups count messages and completions, so only this group's amounts carry a "credits" unit.
    public static let aiCreditsLabel = "AI Credits"

    /// Quota meter fields, worded like the Claude and Codex rows (`20000 credits`, `3% used`).
    public static func metricItems(_ window: QuotaWindow) -> [QuotaNote] {
        var rows: [QuotaNote] = []
        if let entitlement = window.entitlement {
            rows.append(QuotaNote(label: "Entitlement", value: Self.amount(entitlement, in: window)))
        }
        // Only when a percent was reported; `cappedUsedPercent` is the same value the bar draws.
        if window.percentRemaining != nil {
            rows.append(QuotaNote(label: Self.percentUsedLabel, value: QuotaHelpers.formattedPercentUsed(window.cappedUsedPercent)))
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

    public static func overageCountNote(_ window: QuotaWindow) -> QuotaNote? {
        guard let overageCount = window.overageCount, overageCount > 0 else { return nil }
        return QuotaNote(label: "Overage count", value: String(overageCount))
    }

    /// Group captions shown in the menu/CLI (nil for premium_interactions — rows only).
    public static func groupCaption(_ window: QuotaWindow) -> String? {
        (window.label == Self.aiCreditsLabel) ? nil : window.label
    }

    /// All rows for one quota group, in display order.
    public static func displayItems(_ window: QuotaWindow) -> [QuotaNote] {
        var rows = metricItems(window)
        if let note = overagePermittedNote(window) { rows.append(note) }
        if let note = overageLimitNote(window) { rows.append(note) }
        if let note = overageCountNote(window) { rows.append(note) }
        return rows
    }

    /// `20000 credits` for the AI Credits group, a bare count for the free-tier Chat / Completions groups.
    private static func amount(_ count: Int, in window: QuotaWindow) -> String {
        return (window.label == Self.aiCreditsLabel) ? "\(count) credits" : String(count)
    }
}

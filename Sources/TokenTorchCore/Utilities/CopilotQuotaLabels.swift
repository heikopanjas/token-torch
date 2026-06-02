import Foundation

/// Display formatting for GitHub Copilot `quota_snapshots` rows mapped into `QuotaWindow`.
public enum CopilotQuotaLabels {
    /// Quota meter fields only (entitlement / remaining / …).
    public static func metricItems(_ window: QuotaWindow) -> [QuotaNote] {
        var rows: [QuotaNote] = []
        if let entitlement = window.entitlement {
            rows.append(QuotaNote(label: "Entitlement credits", value: String(entitlement)))
        }
        if let remaining = window.remaining {
            rows.append(QuotaNote(label: "Remaining credits", value: String(remaining)))
        }
        if let percentRemaining = window.percentRemaining {
            rows.append(QuotaNote(label: "Percent remaining", value: "\(formatNumber(percentRemaining))%"))
        }
        return rows
    }

    /// Boolean policy row, styled like Claude `Extra usage` (`enabled` / `disabled`).
    public static func overagePermittedNote(_ window: QuotaWindow) -> QuotaNote? {
        guard let permitted = window.overagePermitted else { return nil }
        return QuotaNote(label: "Overage", value: permitted ? "enabled" : "disabled")
    }

    public static func overageCountNote(_ window: QuotaWindow) -> QuotaNote? {
        guard let overageCount = window.overageCount, overageCount > 0 else { return nil }
        return QuotaNote(label: "Overage count", value: String(overageCount))
    }

    /// Group captions shown in the menu/CLI (nil for premium_interactions — rows only).
    public static func groupCaption(_ window: QuotaWindow) -> String? {
        window.label == "AI Credits" ? nil : window.label
    }

    /// All rows for one quota group, in display order.
    public static func displayItems(_ window: QuotaWindow) -> [QuotaNote] {
        var rows = metricItems(window)
        if let note = overagePermittedNote(window) { rows.append(note) }
        if let note = overageCountNote(window) { rows.append(note) }
        return rows
    }

    private static func formatNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

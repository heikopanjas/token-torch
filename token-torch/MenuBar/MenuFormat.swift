import AppKit

enum MenuFormat {
    static let menuWidth: CGFloat = 360
    static let copyButtonSize: CGFloat = 16

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    static func billingCycleDate(_ value: Date) -> String {
        return Self.utcFormatter("yyyy-MM-dd").string(from: value)
    }

    static func billingCycleCaption(start: Date, end: Date) -> String {
        return "Billing cycle: \(Self.billingCycleDate(start)) → \(Self.billingCycleDate(end))"
    }

    static func billingCycleCaption(start: String, end: String?) -> String {
        if let end {
            return "Billing cycle: \(start) → \(end)"
        }
        return "Billing cycle: \(start)"
    }

    static func percentUsed(_ percent: Double, parenthesized: Bool = false) -> String {
        let core = String(format: "%.0f%% used", percent)
        if parenthesized == true {
            return " (\(core))"
        }
        return core
    }

    static func resetTime(_ value: Date) -> String {
        return Self.utcFormatter("yyyy-MM-dd HH:mm").string(from: value) + " UTC"
    }

    /// Caption styled like the org-billing "Billing cycle" line: "resets 2026-06-07 14:11 UTC · in 5d 3h".
    static func resetCaption(_ value: Date) -> String {
        "resets \(resetTime(value)) · \(relativeReset(value))"
    }

    /// Placeholder for a window with no `resets_at` yet (e.g. an idle Claude 5-hour window):
    /// the API only sets a reset time once the window becomes active.
    static let noResetCaption = "resets once the window starts"

    static func relativeReset(_ value: Date) -> String {
        let seconds = Int(value.timeIntervalSinceNow)
        if seconds <= 0 { return "due now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }

    static func orgCost(_ usd: Double, pricing: DisplayPriceOptions) -> String {
        pricing.formatConverted(amount: usd, from: "USD")
    }

    static var captionFont: NSFont { .systemFont(ofSize: NSFont.smallSystemFontSize) }
    static var caption2Font: NSFont { .systemFont(ofSize: 10) }
    static var subheadlineBoldFont: NSFont { .boldSystemFont(ofSize: 13) }
    static var costRowBoldFont: NSFont { .boldSystemFont(ofSize: 11) }
    static var monospacedBoldFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    }
}

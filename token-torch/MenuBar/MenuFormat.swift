import AppKit

enum MenuFormat {
    static let menuWidth: CGFloat = 360

    static func billingCycleDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    static func resetTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: value) + " UTC"
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

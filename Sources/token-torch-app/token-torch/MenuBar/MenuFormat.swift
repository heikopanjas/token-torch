import AppKit
import TokenTorchCore

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

    static func percentColor(_ usedPercent: Double) -> NSColor {
        if usedPercent >= 80 { return .systemRed }
        if usedPercent >= 50 { return .systemYellow }
        return .systemGreen
    }

    static func orgCost(_ usd: Double, in currency: DisplayCurrency) -> String {
        CurrencyConverter.formatConverted(amount: usd, from: "USD", to: currency)
    }

    static var captionFont: NSFont { .systemFont(ofSize: NSFont.smallSystemFontSize) }
    static var caption2Font: NSFont { .systemFont(ofSize: 10) }
    static var subheadlineBoldFont: NSFont { .boldSystemFont(ofSize: 13) }
    static var costRowBoldFont: NSFont { .boldSystemFont(ofSize: 11) }
    static var monospacedBoldFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    }
}

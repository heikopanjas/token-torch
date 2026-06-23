import Foundation

/// A currency the UI can display amounts in. Conversion is supported between these via the
/// built-in USD<->EUR rate; other source currencies are shown natively.
public enum DisplayCurrency: String, Codable, CaseIterable, Sendable {
    case usd = "USD"
    case eur = "EUR"

    public var symbol: String {
        switch self {
            case .usd: "$"
            case .eur: "€"
        }
    }

    public var code: String { rawValue }

    /// The user's locale currency mapped to a supported display currency, falling back to USD.
    public static var systemDefault: DisplayCurrency {
        guard let identifier = Locale.current.currency?.identifier else { return .usd }
        return DisplayCurrency(rawValue: identifier) ?? .usd
    }
}

/// Pure currency conversion + formatting shared by the CLI and the menu bar app.
///
/// Only USD<->EUR conversion is supported (the only rate the app carries). Amounts already in the
/// target currency pass through unchanged; amounts in any other currency are returned/formatted in
/// their native currency rather than being mis-converted.
public enum CurrencyConverter {
    public static func convert(
        amount: Double,
        from sourceCode: String,
        to target: DisplayCurrency,
        rate: Double = Pricing.usdToEUR
    ) -> (amount: Double, code: String) {
        let source = sourceCode.uppercased()
        if source == target.rawValue { return (amount, target.rawValue) }
        switch (source, target) {
            case ("USD", .eur): return (amount * rate, DisplayCurrency.eur.rawValue)
            case ("EUR", .usd): return (amount / rate, DisplayCurrency.usd.rawValue)
            default: return (amount, source)
        }
    }

    /// Formats an amount using the currency symbol for USD/EUR, otherwise `"<CODE> 0.00"`.
    public static func format(amount: Double, code: String) -> String {
        if let currency = DisplayCurrency(rawValue: code.uppercased()) {
            return "\(currency.symbol)\(String(format: "%.2f", amount))"
        }
        return "\(code.uppercased()) \(String(format: "%.2f", amount))"
    }

    public static func formatConverted(
        amount: Double,
        from sourceCode: String,
        to target: DisplayCurrency,
        rate: Double = Pricing.usdToEUR
    ) -> String {
        let converted = convert(amount: amount, from: sourceCode, to: target, rate: rate)
        return format(amount: converted.amount, code: converted.code)
    }

    /// Converts minor units (cents) of `sourceCode` and formats them in `target`.
    public static func formatMinorUnits(
        _ cents: UInt64,
        from sourceCode: String,
        to target: DisplayCurrency,
        rate: Double = Pricing.usdToEUR
    ) -> String {
        formatConverted(amount: Double(cents) / 100.0, from: sourceCode, to: target, rate: rate)
    }
}

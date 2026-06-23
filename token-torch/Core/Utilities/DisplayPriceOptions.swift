import Foundation

/// Currency conversion plus optional VAT adjustment for menu/CLI price display.
///
/// Source amounts from provider APIs are treated as gross (incl. VAT). When
/// `automaticallyDeductVAT` is enabled, displayed values are divided by `1 + vatRatePercent/100`.
public struct DisplayPriceOptions: Sendable, Equatable {
    public var currency: DisplayCurrency
    /// VAT percentage (e.g. 19 for 19%). Clamped to 0...100.
    public var vatRatePercent: Double
    /// When true, deduct VAT from gross vendor prices to show net (ex-VAT) amounts.
    public var automaticallyDeductVAT: Bool

    public init(
        currency: DisplayCurrency,
        vatRatePercent: Double = 0,
        automaticallyDeductVAT: Bool = false
    ) {
        self.currency = currency
        self.vatRatePercent = Self.normalizeVATRate(vatRatePercent)
        self.automaticallyDeductVAT = automaticallyDeductVAT
    }

    public init(preferences: ProviderPreferences) {
        self.init(
            currency: preferences.displayCurrency,
            vatRatePercent: preferences.vatRatePercent,
            automaticallyDeductVAT: preferences.automaticallyDeductVAT
        )
    }

    public static func normalizeVATRate(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    public func amountForDisplay(grossAmount: Double) -> Double {
        guard automaticallyDeductVAT, vatRatePercent > 0 else { return grossAmount }
        return grossAmount / (1 + vatRatePercent / 100)
    }

    public func formatConverted(
        amount: Double,
        from sourceCode: String,
        rate: Double = Pricing.usdToEUR
    ) -> String {
        let converted = CurrencyConverter.convert(amount: amount, from: sourceCode, to: currency, rate: rate)
        let display = amountForDisplay(grossAmount: converted.amount)
        return CurrencyConverter.format(amount: display, code: converted.code)
    }

    public func formatMinorUnits(
        _ cents: UInt64,
        from sourceCode: String,
        rate: Double = Pricing.usdToEUR
    ) -> String {
        formatConverted(amount: Double(cents) / 100.0, from: sourceCode, rate: rate)
    }

    /// Formats a fixed monthly list price such as `$20/mo` with currency conversion and VAT.
    public func formatPlanPrice(_ price: String) -> String {
        guard price.hasSuffix("/mo") else { return price }
        let amountPart = price.dropLast(3).trimmingCharacters(in: CharacterSet(charactersIn: "$€£"))
        guard let amount = Double(amountPart) else { return price }
        return "\(formatConverted(amount: amount, from: "USD"))/mo"
    }
}

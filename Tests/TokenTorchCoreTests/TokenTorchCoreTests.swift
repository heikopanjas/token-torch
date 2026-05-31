import Foundation
import Testing

@testable import TokenTorchCore

@Test func inclusiveEndToRFC3339() throws {
    let value = try DateRange.inclusiveEndToRFC3339(end: "2026-05-31")
    #expect(value == "2026-06-01T00:00:00Z")
}

@Test func startToRFC3339() throws {
    let value = try DateRange.startToRFC3339(start: "2026-05-01")
    #expect(value == "2026-05-01T00:00:00Z")
}

@Test func rfc3339DatePart() {
    #expect(DateRange.rfc3339DatePart("2026-05-01T12:00:00Z") == "2026-05-01")
}

@Test func redactBearerToken() {
    let input = "Auth failed: Bearer sk-admin-abc123xyz done"
    let redacted = Redaction.redactSecrets(input)
    #expect(redacted.contains("Bearer [REDACTED]"))
    #expect(!redacted.contains("sk-admin-abc123xyz"))
}

@Test func mapClaudeUsage() {
    let response = ClaudeQuotaProvider.ClaudeUsageResponse(
        fiveHour: ClaudeQuotaProvider.ClaudeUsageWindow(utilization: 25, resetsAt: "2026-01-28T15:00:00Z"),
        sevenDay: ClaudeQuotaProvider.ClaudeUsageWindow(utilization: 40, resetsAt: "2026-02-01T00:00:00Z"),
        sevenDayOpus: nil,
        sevenDayOmelette: nil,
        extraUsage: nil
    )
    let report = ClaudeQuotaProvider.mapUsage(response, subscriptionType: "pro")
    #expect(report.windows.count == 2)
    #expect(report.planTier == "Pro")
    #expect(report.planPrice == "$20/mo")
}

@Test func mapClaudeUsageSurfacesExtraWindowsAndCredits() {
    func window() -> ClaudeQuotaProvider.ClaudeUsageWindow {
        ClaudeQuotaProvider.ClaudeUsageWindow(utilization: 10, resetsAt: "2026-02-01T00:00:00Z")
    }
    let response = ClaudeQuotaProvider.ClaudeUsageResponse(
        fiveHour: window(),
        sevenDay: window(),
        sevenDaySonnet: window(),
        sevenDayCowork: window(),
        extraUsage: ClaudeQuotaProvider.ClaudeExtraUsage(
            isEnabled: true,
            usedCredits: 327,
            monthlyLimit: 5000,
            utilization: 6.54,
            currency: "EUR"
        )
    )
    let report = ClaudeQuotaProvider.mapUsage(response, subscriptionType: "pro")
    #expect(report.windows.contains { $0.label == "7-day Sonnet window" })
    #expect(report.windows.contains { $0.label == "7-day Cowork window" })
    #expect(report.credits?.usedCents == 327)
    #expect(report.credits?.limitCents == 5000)
    #expect(report.credits?.currency == "EUR")
    #expect(report.credits?.utilizationPercent == 6.54)
}

@Test func currencyConverterConvertsBetweenUsdAndEur() {
    let toEUR = CurrencyConverter.convert(amount: 100, from: "USD", to: .eur)
    #expect(toEUR.code == "EUR")
    #expect(abs(toEUR.amount - 100 * Pricing.usdToEUR) < 0.0001)

    let toUSD = CurrencyConverter.convert(amount: 100, from: "EUR", to: .usd)
    #expect(toUSD.code == "USD")
    #expect(abs(toUSD.amount - 100 / Pricing.usdToEUR) < 0.0001)

    let identity = CurrencyConverter.convert(amount: 42, from: "usd", to: .usd)
    #expect(identity.amount == 42)
    #expect(identity.code == "USD")
}

@Test func currencyConverterPassesThroughUnsupportedSource() {
    let result = CurrencyConverter.convert(amount: 100, from: "GBP", to: .eur)
    #expect(result.amount == 100)
    #expect(result.code == "GBP")
}

@Test func currencyConverterFormatsSymbolsAndCodeFallback() {
    #expect(CurrencyConverter.format(amount: 3.27, code: "EUR") == "€3.27")
    #expect(CurrencyConverter.format(amount: 3.27, code: "USD") == "$3.27")
    #expect(CurrencyConverter.format(amount: 3.27, code: "GBP") == "GBP 3.27")
}

@Test func providerPreferencesDecodesLegacyWithoutDisplayCurrency() throws {
    let legacy = """
        {"claude":{"subscriptionQuotaEnabled":true,"orgBillingEnabled":false},"codex":{"subscriptionQuotaEnabled":true,"orgBillingEnabled":false},"cursor":{"subscriptionQuotaEnabled":true,"orgBillingEnabled":false},"refreshIntervalMinutes":20}
        """
    let prefs = try JSONDecoder().decode(ProviderPreferences.self, from: Data(legacy.utf8))
    #expect(prefs.refreshIntervalMinutes == 20)
    #expect(prefs.displayCurrency == DisplayCurrency.systemDefault)
}

@Test func mapCursorIndividualUsage() {
    let usage = CursorQuotaProvider.CursorUsageResponse(
        billingCycleStart: "1768399334000",
        billingCycleEnd: "1771077734000",
        planUsage: CursorQuotaProvider.CursorPlanUsage(
            includedSpend: 23_222,
            totalSpend: 57_318,
            bonusSpend: 17_318,
            remaining: 16_778,
            limit: 40_000,
            autoPercentUsed: 0,
            apiPercentUsed: 46.444,
            totalPercentUsed: 15.48
        ),
        spendLimitUsage: nil,
        displayMessage: "You've used 46% of your usage limit"
    )
    let plan = CursorQuotaProvider.CursorPlanResponse(
        planInfo: CursorQuotaProvider.CursorPlanInfo(
            planName: "Ultra",
            includedAmountCents: 40_000,
            price: "$200/mo",
            billingCycleEnd: "1771077734000"
        )
    )
    let report = CursorQuotaProvider.mapUsage(usage: usage, plan: plan, membershipType: "ultra")
    #expect(report.planTier == "Ultra")
    #expect(report.apiAllowance?.usedCents == 18_578)
    #expect(report.periodSpendCents == 23_222)
    #expect(report.totalSpendCents == 57_318)
    #expect(report.bonusSpendCents == 17_318)
}

@Test func mapCodexUsageFromSnakeCaseJSON() throws {
    let json = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":6,"reset_at":1738300000},"secondary_window":{"used_percent":24,"reset_at":1738900000}},"code_review_rate_limit":null,"credits":{"has_credits":false,"balance":"0"}}
        """
    let response = try JSONDecoder().decode(CodexQuotaProvider.ChatGptUsageResponse.self, from: Data(json.utf8))
    let report = CodexQuotaProvider.mapUsage(response)
    #expect(report.windows.count == 2)
    #expect(report.planTier == "Pro Lite")
    #expect(report.planPrice == "$100/mo")
}

@Test func mapChatGptSurfacesNotesAndAdditionalWindows() throws {
    let json = """
        {"user_id":"user-x","account_id":"acc","email":"a@b.com","plan_type":"prolite",
        "rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":0,"reset_at":1780254481},"secondary_window":{"used_percent":0,"reset_at":1780841281}},
        "code_review_rate_limit":null,
        "additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_bengalfox","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":0,"reset_at":1780254481},"secondary_window":{"used_percent":0,"reset_at":1780841281}}}],
        "credits":{"has_credits":false,"unlimited":false,"overage_limit_reached":false,"balance":"0","approx_local_messages":[0,0],"approx_cloud_messages":[0,0]},
        "spend_control":{"reached":false,"individual_limit":null},
        "rate_limit_reached_type":null,"promo":null,"referral_beacon":null,"rate_limit_reset_credits":{"available_count":0}}
        """
    let response = try JSONDecoder().decode(CodexQuotaProvider.ChatGptUsageResponse.self, from: Data(json.utf8))
    let report = CodexQuotaProvider.mapUsage(response)
    // Additional per-model limits live in additionalWindows (opt-in display), not the main windows.
    #expect(report.additionalWindows.contains { $0.label == "GPT-5.3-Codex-Spark (5h)" })
    #expect(report.additionalWindows.contains { $0.label == "GPT-5.3-Codex-Spark (7d)" })
    #expect(!report.windows.contains { $0.label.contains("Spark") })
    // D7: healthy state hides the boolean status notes entirely.
    #expect(report.notes.isEmpty)
}

@Test func mapChatGptSurfacesStatusNotesOnlyWhenLimited() throws {
    let json = """
        {"plan_type":"pro",
        "rate_limit":{"allowed":false,"limit_reached":true,"primary_window":{"used_percent":100,"reset_at":1780254481},"secondary_window":{"used_percent":50,"reset_at":1780841281}},
        "code_review_rate_limit":{"primary_window":{"used_percent":10,"reset_at":1780254481},"secondary_window":{"used_percent":5,"reset_at":1780841281}},
        "credits":{"has_credits":true,"unlimited":true,"overage_limit_reached":true,"balance":"12.5"},
        "spend_control":{"reached":true,"individual_limit":500},
        "rate_limit_reached_type":"secondary","promo":null}
        """
    let response = try JSONDecoder().decode(CodexQuotaProvider.ChatGptUsageResponse.self, from: Data(json.utf8))
    let report = CodexQuotaProvider.mapUsage(response)
    #expect(report.notes.contains { $0.label == "Rate limited" })
    #expect(report.notes.contains { $0.label == "Limit reached" })
    #expect(report.notes.contains { $0.label == "Rate limit type" && $0.value == "weekly limit" })
    #expect(report.notes.contains { $0.label == "Unlimited credits" })
    #expect(report.notes.contains { $0.label == "Overage limit reached" })
    #expect(report.notes.contains { $0.label == "Spend control reached" })
    #expect(report.notes.contains { $0.label == "Spend limit" })
    // D1: code review windows surface when non-null.
    #expect(report.windows.contains { $0.label == "Code review (5h)" })
}

@Test func mapClaudeSurfacesExtraUsageNoteAndExcludesSensitive() {
    let response = ClaudeQuotaProvider.ClaudeUsageResponse(
        fiveHour: ClaudeQuotaProvider.ClaudeUsageWindow(utilization: 0, resetsAt: "2026-05-31T17:40:00.947309+00:00"),
        sevenDay: ClaudeQuotaProvider.ClaudeUsageWindow(utilization: 3, resetsAt: "2026-06-05T09:00:00.947345+00:00"),
        extraUsage: ClaudeQuotaProvider.ClaudeExtraUsage(
            isEnabled: false,
            usedCredits: nil,
            monthlyLimit: nil,
            utilization: nil,
            currency: nil
        )
    )
    let report = ClaudeQuotaProvider.mapUsage(response, subscriptionType: "pro")
    #expect(report.notes.contains { $0.label == "Extra usage" && $0.value == "disabled" })
    #expect(report.credits == nil)
    #expect(!report.notes.contains { $0.label.contains("currency") || $0.label.contains("disabled_reason") })
    // Microsecond-precision resets_at parses to a real date (no "resets unknown").
    #expect(report.windows.first { $0.label == "7-day window" }?.resetsAt != nil)
}

@Test func parseRFC3339ParsesFractionalSeconds() {
    #expect(QuotaHelpers.parseRFC3339UTC("2026-06-05T09:00:00.947345+00:00") != nil)
    #expect(QuotaHelpers.parseRFC3339UTC("2026-06-05T09:00:00.123Z") != nil)
    #expect(QuotaHelpers.parseRFC3339UTC("2026-06-05T09:00:00Z") != nil)
}

@Test func quotaAuthErrorIgnoresResetAtSubstring() {
    let decodeError = TokenTorchError.message("Invalid GET response: {\"reset_at\":1780403740}")
    #expect(QuotaHTTP.isQuotaAuthError(decodeError, policy: .standard) == false)
    let authError = TokenTorchError.message("GET failed (403): forbidden")
    #expect(QuotaHTTP.isQuotaAuthError(authError, policy: .standard) == true)
}

@Test func decodeOpenAICostAmountFromString() throws {
    let json = """
        {"value":"0.003776000000000000000000000000000000","currency":"usd"}
        """
    let amount = try JSONDecoder().decode(OpenAIOrgProvider.CostAmount.self, from: Data(json.utf8))
    #expect(abs(amount.value - 0.003776) < 0.000001)
}

@Test func decodeOpenAICostAmountScientificZero() throws {
    let json = #"{"value":"0E-6176","currency":"usd"}"#
    let amount = try JSONDecoder().decode(OpenAIOrgProvider.CostAmount.self, from: Data(json.utf8))
    #expect(amount.value == 0)
}

@Test func keychainResetTargetsOnlyTokenTorchServices() {
    #expect(TokenTorchKeychainMaintenance.isTokenTorchService("com.tokentorch.keys.claude.adminKey"))
    #expect(TokenTorchKeychainMaintenance.isTokenTorchService("com.tokentorch.vendor.cursor.oauth"))
    // Vendor-owned items must never be considered Token Torch's.
    #expect(!TokenTorchKeychainMaintenance.isTokenTorchService("Claude Code-credentials-bde0ee9f"))
    #expect(!TokenTorchKeychainMaintenance.isTokenTorchService("Codex Auth"))
    #expect(!TokenTorchKeychainMaintenance.isTokenTorchService("cursor-access-token"))
    #expect(!TokenTorchKeychainMaintenance.isTokenTorchService(""))
    #expect(!TokenTorchKeychainMaintenance.isTokenTorchService("com.burn.keys.claude.adminKey"))
}

@Test func appKeychainStoreRoundTrip() throws {
    let store = InMemoryAppKeychainStore()
    try store.save(provider: .claude, kind: .adminKey, value: "sk-test-admin")
    let loaded = try store.load(provider: .claude, kind: .adminKey)
    #expect(loaded == "sk-test-admin")
}

@Test func vendorCredentialCacheInvalidateProvider() {
    let session = OAuthSession(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: nil,
        accountID: nil,
        subscriptionType: nil,
        rateLimitTier: nil,
        source: .tokenTorchCopy
    )
    VendorCredentialCache.storeClaude(session)
    #expect(VendorCredentialCache.claudeSession() != nil)
    VendorCredentialCache.invalidate(provider: .claude)
    #expect(VendorCredentialCache.claudeSession() == nil)
}

@Test func ensureImportedSkipsWhenQuotaDisabled() throws {
    try VendorCredentialImporter.ensureImported(provider: .cursor, quotaEnabled: false)
}

@Test func ensureImportedForEnabledProvidersSkipsDisabledProviders() throws {
    var preferences = ProviderPreferences()
    preferences.claude = ProviderModeFlags(subscriptionQuotaEnabled: false, orgBillingEnabled: false)
    preferences.codex = ProviderModeFlags(subscriptionQuotaEnabled: false, orgBillingEnabled: false)
    preferences.cursor = ProviderModeFlags(subscriptionQuotaEnabled: false, orgBillingEnabled: false)
    try VendorCredentialImporter.ensureImportedForEnabledProviders(preferences: preferences)
}

@Test func ensureImportedForEnabledProvidersNonInteractiveSkipsDisabledProviders() throws {
    var preferences = ProviderPreferences()
    preferences.claude = ProviderModeFlags(subscriptionQuotaEnabled: false, orgBillingEnabled: false)
    preferences.codex = ProviderModeFlags(subscriptionQuotaEnabled: false, orgBillingEnabled: false)
    preferences.cursor = ProviderModeFlags(subscriptionQuotaEnabled: false, orgBillingEnabled: false)
    try VendorCredentialImporter.ensureImportedForEnabledProviders(preferences: preferences, interactive: false)
}

@Test func resetAndReimportWithQuotaDisabledOnlyResets() throws {
    try VendorCredentialImporter.resetAndReimport(provider: .cursor, quotaEnabled: false, interactive: false)
}

@Test func requireUsableSessionThrowsForExpiredToken() {
    let expired = OAuthSession(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: 1,
        accountID: nil,
        subscriptionType: nil,
        rateLimitTier: nil,
        source: .tokenTorchCopy
    )
    #expect(throws: TokenTorchError.self) {
        try QuotaHTTP.requireUsableSession(expired, provider: "Claude Code", vendorAction: "Re-login with Claude Code (/login).")
    }
}

@Test func requireUsableSessionAllowsTokenWithoutExpiry() throws {
    let session = OAuthSession(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: nil,
        accountID: nil,
        subscriptionType: nil,
        rateLimitTier: nil,
        source: .tokenTorchCopy
    )
    try QuotaHTTP.requireUsableSession(session, provider: "Claude Code", vendorAction: "Re-login with Claude Code (/login).")
}

@Test func needsAuthorizationErrorMentionsProviderAndRefresh() {
    let description = TokenTorchError.needsAuthorization(provider: .claude).errorDescription ?? ""
    #expect(description.contains("Claude"))
    #expect(description.contains("Refresh"))
}

@Test func freshestPrefersLaterExpiryOverStaleSameServiceItem() {
    // Mirrors the real bug: a stale leftover item (account "burn") shadowing Claude Code's live
    // login under the same Keychain service. The freshest (future-expiry) session must win.
    let stale = OAuthSession(
        accessToken: "stale",
        refreshToken: "refresh",
        expiresAt: 1_779_815_162_327,
        accountID: nil,
        subscriptionType: nil,
        rateLimitTier: nil,
        source: .claudeKeychain(service: "Claude Code-credentials-bde0ee9f")
    )
    let live = OAuthSession(
        accessToken: "live",
        refreshToken: "refresh",
        expiresAt: 1_780_260_684_949,
        accountID: nil,
        subscriptionType: nil,
        rateLimitTier: nil,
        source: .claudeKeychain(service: "Claude Code-credentials-bde0ee9f")
    )
    #expect(VendorCredentialsReader.freshest([stale, live])?.accessToken == "live")
    #expect(VendorCredentialsReader.freshest([live, stale])?.accessToken == "live")
    #expect(VendorCredentialsReader.freshest([]) == nil)
}

@Test func sessionIsUsableHonorsExpiry() {
    let expired = OAuthSession(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: 1,
        accountID: nil,
        subscriptionType: nil,
        rateLimitTier: nil,
        source: .tokenTorchCopy
    )
    #expect(VendorCredentialsReader.sessionIsUsable(expired) == false)
}

@Test func planBrandingMapsChatGptCodesToBrandNames() {
    #expect(PlanBranding.chatGPT("go") == "Go")
    #expect(PlanBranding.chatGPT("plus") == "Plus")
    #expect(PlanBranding.chatGPT("pro") == "Pro")
    #expect(PlanBranding.chatGPT("prolite") == "Pro Lite")
    #expect(PlanBranding.chatGPT("team") == "Team")
    #expect(PlanBranding.chatGPT("quorum") == "Quorum")  // unknown -> capitalized fallback
    #expect(PlanBranding.chatGPT(nil) == nil)
}

@Test func planBrandingMapsClaudeMaxTierWithMultiplier() {
    #expect(PlanBranding.claude(subscriptionType: "pro", rateLimitTier: nil) == "Pro")
    #expect(PlanBranding.claude(subscriptionType: "max", rateLimitTier: nil) == "Max")
    #expect(PlanBranding.claude(subscriptionType: "max", rateLimitTier: "default_claude_max_5x") == "Max 5x")
    #expect(PlanBranding.claude(subscriptionType: "max", rateLimitTier: "default_claude_max_20x") == "Max 20x")
    #expect(PlanBranding.claude(subscriptionType: nil, rateLimitTier: nil) == nil)
}

@Test func planBrandingMapsMonthlyPrices() {
    #expect(PlanBranding.chatGPTPrice("go") == "$8/mo")
    #expect(PlanBranding.chatGPTPrice("plus") == "$20/mo")
    #expect(PlanBranding.chatGPTPrice("prolite") == "$100/mo")
    #expect(PlanBranding.chatGPTPrice("pro") == "$200/mo")
    #expect(PlanBranding.chatGPTPrice("team") == nil)
    #expect(PlanBranding.chatGPTPrice("free") == nil)
    #expect(PlanBranding.chatGPTPrice(nil) == nil)

    #expect(PlanBranding.claudePrice(subscriptionType: "pro", rateLimitTier: nil) == "$20/mo")
    #expect(PlanBranding.claudePrice(subscriptionType: "max", rateLimitTier: "default_claude_max_5x") == "$100/mo")
    #expect(PlanBranding.claudePrice(subscriptionType: "max", rateLimitTier: "default_claude_max_20x") == "$200/mo")
    #expect(PlanBranding.claudePrice(subscriptionType: "max", rateLimitTier: nil) == nil)
    #expect(PlanBranding.claudePrice(subscriptionType: "team", rateLimitTier: nil) == nil)
}

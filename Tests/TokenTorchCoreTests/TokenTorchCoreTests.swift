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
    #expect(report.planTier == "pro")
}

@Test func mapCursorIndividualUsage() {
    let usage = CursorQuotaProvider.CursorUsageResponse(
        billingCycleStart: "1768399334000",
        billingCycleEnd: "1771077734000",
        planUsage: CursorQuotaProvider.CursorPlanUsage(
            includedSpend: 23_222,
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
}

@Test func mapCodexUsageFromSnakeCaseJSON() throws {
    let json = """
        {"plan_type":"prolite","rate_limit":{"primary_window":{"used_percent":6,"reset_at":1738300000},"secondary_window":{"used_percent":24,"reset_at":1738900000}},"code_review_rate_limit":null,"credits":{"has_credits":false,"balance":"0"}}
        """
    let response = try JSONDecoder().decode(CodexQuotaProvider.ChatGptUsageResponse.self, from: Data(json.utf8))
    let report = CodexQuotaProvider.mapUsage(response)
    #expect(report.windows.count == 2)
    #expect(report.planTier == "prolite")
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

@Test func sessionIsUsableHonorsExpiry() {
    let expired = OAuthSession(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: 1,
        accountID: nil,
        subscriptionType: nil,
        source: .tokenTorchCopy
    )
    #expect(VendorCredentialsReader.sessionIsUsable(expired) == false)
}

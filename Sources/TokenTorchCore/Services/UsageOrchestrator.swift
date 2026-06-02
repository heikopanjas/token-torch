import Foundation

public final class ProviderPreferencesStore: @unchecked Sendable {
    public static let shared = ProviderPreferencesStore()
    private let defaults: UserDefaults
    private let key = AppBrand.preferencesKey

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ProviderPreferences {
        guard let data = defaults.data(forKey: key),
            let prefs = try? JSONDecoder().decode(ProviderPreferences.self, from: data)
        else {
            return ProviderPreferences()
        }
        return prefs
    }

    public func save(_ preferences: ProviderPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}

public struct UsageOrchestrator: Sendable {
    public let preferencesStore: ProviderPreferencesStore
    public let keychain: AppKeychainStoring
    public let credentialStrategy: VendorCredentialStrategy

    public init(
        preferencesStore: ProviderPreferencesStore = .shared,
        keychain: AppKeychainStoring = AppKeychainStore.shared,
        credentialStrategy: VendorCredentialStrategy = .directVendorRead
    ) {
        self.preferencesStore = preferencesStore
        self.keychain = keychain
        self.credentialStrategy = credentialStrategy
    }

    /// Fetches all enabled providers.
    /// - Parameter interactive: when `false` (startup/timer refresh) no credential access prompts;
    ///   providers without a silent source surface a `needsAuthorization` report instead of an error.
    public func fetchAll(preferences: ProviderPreferences? = nil, interactive: Bool = false) async -> AllProvidersResult {
        let prefs = preferences ?? preferencesStore.load()
        var results: [ProviderFetchResult] = []

        await withTaskGroup(of: ProviderFetchResult?.self) { group in
            for provider in ProviderID.allCases {
                group.addTask {
                    await self.fetchProvider(provider, preferences: prefs, interactive: interactive)
                }
            }
            for await item in group {
                if let item { results.append(item) }
            }
        }

        return AllProvidersResult(
            results: results.sorted { prefs.providerOrderIndex(of: $0.provider) < prefs.providerOrderIndex(of: $1.provider) })
    }

    private func fetchProvider(_ provider: ProviderID, preferences: ProviderPreferences, interactive: Bool) async -> ProviderFetchResult? {
        let flags = preferences.flags(for: provider)
        guard flags.subscriptionQuotaEnabled || flags.orgBillingEnabled else { return nil }

        var reports: [ProviderReport] = []

        if flags.subscriptionQuotaEnabled {
            reports.append(await subscriptionReport(provider: provider, interactive: interactive))
        }

        if flags.orgBillingEnabled {
            guard provider.supportsOrgBilling else { return ProviderFetchResult(provider: provider, reports: reports) }
            do {
                let (start, end) = try DateRange.parseDateRange(startInput: nil, endInput: nil)
                let adminKey = try requireAdminKey(provider: provider)
                let org = try await fetchOrg(provider: provider, adminKey: adminKey, start: start, end: end)
                reports.append(.org(org))
            }
            catch {
                reports.append(.error(provider: provider, mode: "org billing", message: Redaction.redactSecrets(error.localizedDescription)))
            }
        }

        return ProviderFetchResult(provider: provider, reports: reports)
    }

    private func subscriptionReport(provider: ProviderID, interactive: Bool) async -> ProviderReport {
        if credentialStrategy == .tokenTorchOwnedCopy, provider != .copilot {
            do {
                try VendorCredentialImporter.ensureImported(
                    provider: provider,
                    quotaEnabled: true,
                    interactive: interactive
                )
            }
            catch {
                if !interactive, Self.isNeedsAuthorization(error) {
                    return .needsAuthorization(provider: provider, mode: "subscription")
                }
                // Interactive failures fall through; the fetch below surfaces a precise error.
            }
        }
        do {
            let quota = try await fetchQuota(provider: provider, interactive: interactive)
            return .subscription(quota)
        }
        catch {
            if !interactive, Self.isNeedsAuthorization(error) {
                return .needsAuthorization(provider: provider, mode: "subscription")
            }
            return .error(provider: provider, mode: "subscription", message: Redaction.redactSecrets(error.localizedDescription))
        }
    }

    private static func isNeedsAuthorization(_ error: Error) -> Bool {
        guard let error = error as? TokenTorchError else { return false }
        switch error {
            case .needsAuthorization, .missingCredentials: return true
            default: return false
        }
    }

    private func fetchQuota(provider: ProviderID, interactive: Bool) async throws -> SubscriptionQuotaReport {
        switch provider {
            case .claude:
                return try await ClaudeQuotaProvider.fetch(credentialStrategy: credentialStrategy, interactive: interactive)
            case .codex:
                return try await CodexQuotaProvider.fetch(credentialStrategy: credentialStrategy, interactive: interactive)
            case .cursor:
                return try await CursorQuotaProvider.fetch(credentialStrategy: credentialStrategy, interactive: interactive)
            case .copilot:
                let token = try requirePersonalAccessToken()
                return try await CopilotQuotaProvider.fetch(personalAccessToken: token)
        }
    }

    private func requirePersonalAccessToken() throws -> String {
        guard
            let token = try keychain.load(provider: .copilot, kind: .personalAccessToken),
            !token.isEmpty
        else {
            throw TokenTorchError.missingPersonalAccessToken(provider: .copilot)
        }
        return token
    }

    private func requireAdminKey(provider: ProviderID) throws -> String {
        guard let key = try keychain.load(provider: provider, kind: .adminKey), !key.isEmpty else {
            throw TokenTorchError.missingAdminKey(provider: provider)
        }
        return key
    }

    private func fetchOrg(provider: ProviderID, adminKey: String, start: String, end: String?) async throws -> OrgUsageReport {
        switch provider {
            case .claude:
                return try await AnthropicOrgProvider.fetchOrgReport(
                    adminKey: adminKey, startDate: start, endDate: end, workspaceID: nil
                )
            case .codex:
                return try await OpenAIOrgProvider.fetchOrgReport(
                    adminKey: adminKey, startDate: start, endDate: end, projectID: nil
                )
            case .cursor:
                throw TokenTorchError.unsupported("Cursor organization billing is not available.")
            case .copilot:
                throw TokenTorchError.unsupported("Copilot organization billing is not available.")
        }
    }
}

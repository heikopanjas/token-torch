import Foundation

/// Imports vendor OAuth into Token Torch-owned Keychain copies (read-only vendor access).
public enum VendorCredentialImporter {
    /// Ensures a usable Token Torch-owned copy exists for `provider`.
    /// - Parameter interactive: controls how missing credentials are surfaced. Vendor Keychain
    ///   fallbacks use `/usr/bin/security` for both automatic and interactive imports.
    public static func ensureImported(provider: ProviderID, quotaEnabled: Bool, interactive: Bool = false) async throws {
        guard quotaEnabled == true else { return }
        guard provider != .copilot else { return }

        if let cached = VendorCredentialCache.session(for: provider),
            sessionIsUsable(cached)
        {
            return
        }
        if let stored = try TokenTorchVendorCredentialStore.load(provider: provider),
            sessionIsUsable(stored)
        {
            VendorCredentialCache.store(stored, for: provider)
            return
        }
        do {
            _ = try await Self.importAndSave(provider: provider, interactive: interactive)
        }
        catch let error as TokenTorchError {
            if interactive == false, case .missingCredentials = error {
                throw TokenTorchError.needsAuthorization(provider: provider)
            }
            throw error
        }
    }

    public static func reset(provider: ProviderID) throws {
        try TokenTorchVendorCredentialStore.delete(provider: provider)
        VendorCredentialImportSourceStore.delete(provider: provider)
        VendorCredentialCache.invalidate(provider: provider)
    }

    public static func resetAndReimport(provider: ProviderID, quotaEnabled: Bool, interactive: Bool = false) async throws {
        try Self.reset(provider: provider)
        guard quotaEnabled == true else { return }
        _ = try await Self.importAndSave(provider: provider, interactive: interactive)
    }

    public static func reimportAfterAuthFailure(provider: ProviderID, interactive: Bool = false) async throws -> OAuthSession {
        try Self.reset(provider: provider)
        return try await Self.importAndSave(provider: provider, interactive: interactive)
    }

    public static func ensureImportedForEnabledProviders(preferences: ProviderPreferences, interactive: Bool = false) async throws {
        for provider in ProviderID.allCases {
            try await Self.ensureImported(
                provider: provider,
                quotaEnabled: preferences.flags(for: provider).subscriptionQuotaEnabled,
                interactive: interactive
            )
        }
    }

    private static func importAndSave(provider: ProviderID, interactive: Bool) async throws -> OAuthSession {
        let imported = try await Self.importFromVendor(provider: provider, interactive: interactive)
        let session = OAuthSession(
            accessToken: imported.accessToken,
            refreshToken: imported.refreshToken,
            expiresAt: imported.expiresAt,
            accountID: imported.accountID,
            subscriptionType: imported.subscriptionType,
            rateLimitTier: imported.rateLimitTier,
            source: imported.source
        )
        try TokenTorchVendorCredentialStore.save(provider: provider, session: session)
        VendorCredentialImportSourceStore.save(imported.source, provider: provider)
        VendorCredentialCache.store(session, for: provider)
        return session
    }

    private static func importFromVendor(provider: ProviderID, interactive: Bool) async throws -> OAuthSession {
        switch provider {
            case .claude: return try await VendorCredentialsReader.importClaudeSessionFromVendor(interactive: interactive)
            case .codex: return try await VendorCredentialsReader.importCodexSessionFromVendor(interactive: interactive)
            case .cursor: return try await VendorCredentialsReader.importCursorSessionFromVendor(interactive: interactive)
            case .copilot:
                throw TokenTorchError.unsupported("Copilot uses a GitHub Personal Access Token, not vendor OAuth.")
        }
    }

    private static func sessionIsUsable(_ session: OAuthSession) -> Bool {
        VendorCredentialsReader.sessionIsUsable(session)
    }
}

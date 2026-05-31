import Foundation

/// Imports vendor OAuth into Token Torch-owned Keychain copies (read-only vendor access).
public enum VendorCredentialImporter {
    /// Ensures a usable Token Torch-owned copy exists for `provider`.
    /// - Parameter interactive: when `false` (startup/timer), vendor Keychain reads never prompt;
    ///   if no silent source is available the call throws `TokenTorchError.needsAuthorization`.
    public static func ensureImported(provider: ProviderID, quotaEnabled: Bool, interactive: Bool = false) throws {
        guard quotaEnabled else { return }

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
            _ = try importAndSave(provider: provider, interactive: interactive)
        }
        catch let error as TokenTorchError {
            if !interactive, case .missingCredentials = error {
                throw TokenTorchError.needsAuthorization(provider: provider)
            }
            throw error
        }
    }

    public static func reset(provider: ProviderID) throws {
        try TokenTorchVendorCredentialStore.delete(provider: provider)
        VendorCredentialCache.invalidate(provider: provider)
    }

    public static func resetAndReimport(provider: ProviderID, quotaEnabled: Bool, interactive: Bool = false) throws {
        try reset(provider: provider)
        guard quotaEnabled else { return }
        _ = try importAndSave(provider: provider, interactive: interactive)
    }

    public static func reimportAfterAuthFailure(provider: ProviderID, interactive: Bool = false) throws -> OAuthSession {
        try reset(provider: provider)
        return try importAndSave(provider: provider, interactive: interactive)
    }

    public static func ensureImportedForEnabledProviders(preferences: ProviderPreferences, interactive: Bool = false) throws {
        for provider in ProviderID.allCases {
            try ensureImported(
                provider: provider,
                quotaEnabled: preferences.flags(for: provider).subscriptionQuotaEnabled,
                interactive: interactive
            )
        }
    }

    private static func importAndSave(provider: ProviderID, interactive: Bool) throws -> OAuthSession {
        let imported = try importFromVendor(provider: provider, interactive: interactive)
        let session = OAuthSession(
            accessToken: imported.accessToken,
            refreshToken: imported.refreshToken,
            expiresAt: imported.expiresAt,
            accountID: imported.accountID,
            subscriptionType: imported.subscriptionType,
            rateLimitTier: imported.rateLimitTier,
            source: .tokenTorchCopy
        )
        try TokenTorchVendorCredentialStore.save(provider: provider, session: session)
        VendorCredentialCache.store(session, for: provider)
        return session
    }

    private static func importFromVendor(provider: ProviderID, interactive: Bool) throws -> OAuthSession {
        switch provider {
            case .claude: try VendorCredentialsReader.importClaudeSessionFromVendor(allowUI: interactive)
            case .codex: try VendorCredentialsReader.importCodexSessionFromVendor(allowUI: interactive)
            case .cursor: try VendorCredentialsReader.importCursorSessionFromVendor(allowUI: interactive)
        }
    }

    private static func sessionIsUsable(_ session: OAuthSession) -> Bool {
        VendorCredentialsReader.sessionIsUsable(session)
    }
}

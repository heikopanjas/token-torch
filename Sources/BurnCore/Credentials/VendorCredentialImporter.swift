import Foundation

/// Imports vendor OAuth into burn-owned Keychain copies (read-only vendor access).
public enum VendorCredentialImporter {
    public static func ensureImported(provider: ProviderID, quotaEnabled: Bool) throws {
        guard quotaEnabled else { return }

        if let cached = VendorCredentialCache.session(for: provider),
            sessionIsUsable(cached)
        {
            return
        }
        if try BurnVendorCredentialStore.isFresh(provider: provider),
            let stored = try BurnVendorCredentialStore.load(provider: provider)
        {
            VendorCredentialCache.store(stored, for: provider)
            return
        }
        _ = try importAndSave(provider: provider)
    }

    public static func reset(provider: ProviderID) throws {
        try BurnVendorCredentialStore.delete(provider: provider)
        VendorCredentialCache.invalidate(provider: provider)
    }

    public static func resetAndReimport(provider: ProviderID, quotaEnabled: Bool) throws {
        try reset(provider: provider)
        guard quotaEnabled else { return }
        _ = try importAndSave(provider: provider)
    }

    public static func reimportAfterAuthFailure(provider: ProviderID) throws -> OAuthSession {
        try reset(provider: provider)
        return try importAndSave(provider: provider)
    }

    public static func ensureImportedForEnabledProviders(preferences: ProviderPreferences) throws {
        for provider in ProviderID.allCases {
            try ensureImported(
                provider: provider,
                quotaEnabled: preferences.flags(for: provider).subscriptionQuotaEnabled
            )
        }
    }

    private static func importAndSave(provider: ProviderID) throws -> OAuthSession {
        let imported = try importFromVendor(provider: provider)
        let session = OAuthSession(
            accessToken: imported.accessToken,
            refreshToken: imported.refreshToken,
            expiresAt: imported.expiresAt,
            accountID: imported.accountID,
            subscriptionType: imported.subscriptionType,
            source: .burnCopy
        )
        try BurnVendorCredentialStore.save(provider: provider, session: session)
        VendorCredentialCache.store(session, for: provider)
        return session
    }

    private static func importFromVendor(provider: ProviderID) throws -> OAuthSession {
        switch provider {
            case .claude: try VendorCredentialsReader.importClaudeSessionFromVendor()
            case .codex: try VendorCredentialsReader.importCodexSessionFromVendor()
            case .cursor: try VendorCredentialsReader.importCursorSessionFromVendor()
        }
    }

    private static func sessionIsUsable(_ session: OAuthSession) -> Bool {
        VendorCredentialsReader.sessionIsUsable(session)
    }
}

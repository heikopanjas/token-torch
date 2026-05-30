import Foundation

/// One-time migration of Keychain entries from legacy `com.burn.*` services.
public enum CredentialStoreMigration {
    private static let legacyAccount = "burn"

    public static func migrateFromBurnIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: AppBrand.migrationFlagKey) else { return }

        for provider in ProviderID.allCases {
            _ = migrateVendorOAuth(provider: provider)
            _ = migrateAdminKeys(provider: provider)
        }
        _ = migratePreferences()

        UserDefaults.standard.set(true, forKey: AppBrand.migrationFlagKey)
    }

    private static func migrateVendorOAuth(provider: ProviderID) -> Bool {
        let newService = TokenTorchVendorCredentialStore.service(for: provider)
        guard (try? TokenTorchVendorCredentialStore.load(provider: provider)) == nil else { return false }
        let legacyService = "com.burn.vendor.\(provider.rawValue).oauth"
        guard
            let value = try? KeychainReader.readGenericPassword(
                service: legacyService,
                account: legacyAccount
            )
        else {
            return false
        }
        try? KeychainReader.saveGenericPassword(
            service: newService,
            account: AppBrand.keychainAccount,
            value: value
        )
        return true
    }

    private static func migrateAdminKeys(provider: ProviderID) -> Bool {
        var migrated = false
        for kind in [AppKeyKind.adminKey] where (try? AppKeychainStore.shared.hasKey(provider: provider, kind: kind)) != true {
            let legacyService = "com.burn.keys.\(provider.rawValue).\(kind.rawValue)"
            guard
                let value = try? KeychainReader.readGenericPassword(
                    service: legacyService,
                    account: legacyAccount
                )
            else {
                continue
            }
            try? AppKeychainStore.shared.save(provider: provider, kind: kind, value: value)
            migrated = true
        }
        return migrated
    }

    private static func migratePreferences() -> Bool {
        let legacyKey = "burn.providerPreferences"
        guard UserDefaults.standard.data(forKey: AppBrand.preferencesKey) == nil,
            let data = UserDefaults.standard.data(forKey: legacyKey)
        else {
            return false
        }
        UserDefaults.standard.set(data, forKey: AppBrand.preferencesKey)
        return true
    }
}

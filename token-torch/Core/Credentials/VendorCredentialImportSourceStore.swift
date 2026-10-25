import Foundation

/// Records which vendor source each subscription credential was imported from. Claude repair uses it to pick
/// the matching `CLAUDE_CONFIG_DIR`; keychain reset clears it together with the credential cache.
enum VendorCredentialImportSourceStore {
    private static let keyPrefix = "tokentorch.vendorImportSource."

    static func load(provider: ProviderID, defaults: UserDefaults = .standard) -> CredentialSource? {
        guard let data = defaults.data(forKey: key(for: provider)) else { return nil }
        return try? JSONDecoder().decode(CredentialSource.self, from: data)
    }

    static func save(_ source: CredentialSource, provider: ProviderID, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(source) else { return }
        defaults.set(data, forKey: key(for: provider))
    }

    static func delete(provider: ProviderID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: provider))
    }

    static func deleteAll(defaults: UserDefaults = .standard) {
        for provider in ProviderID.allCases {
            delete(provider: provider, defaults: defaults)
        }
    }

    private static func key(for provider: ProviderID) -> String {
        "\(keyPrefix)\(provider.rawValue)"
    }
}

import Foundation
import Security

struct KeychainGenericPasswordMetadata: Sendable, Equatable {
    let service: String
    let account: String?
    let label: String?
    let itemDescription: String?
    let comment: String?
    let createdAt: Date?
    let modifiedAt: Date?
    let accessible: String?
    let accessGroup: String?
    let synchronizable: Bool?
}

struct KeychainMetadataQueryResult: Sendable, Equatable {
    let status: Int32
    let items: [KeychainGenericPasswordMetadata]

    var statusLabel: String {
        switch status {
            case errSecSuccess: "Success"
            case errSecItemNotFound: "Not found"
            case errSecAuthFailed: "Authentication failed"
            case errSecUserCanceled: "User canceled"
            case errSecInteractionNotAllowed: "Interaction not allowed"
            default: "Keychain status \(status)"
        }
    }
}

struct VendorCredentialSourceInfo: Sendable, Equatable {
    enum SourceKind: String, Sendable {
        case file = "File"
        case keychain = "Keychain"
        case sqlite = "SQLite"
    }

    struct Detail: Sendable, Equatable {
        let label: String
        let value: String
    }

    let provider: ProviderID
    let title: String
    let kind: SourceKind
    let status: String
    let details: [Detail]
}

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

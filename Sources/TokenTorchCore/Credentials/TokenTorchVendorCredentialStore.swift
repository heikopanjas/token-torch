import Foundation

/// Token Torch-owned Keychain storage for imported vendor OAuth sessions (`com.tokentorch.vendor.*`).
public enum TokenTorchVendorCredentialStore {
    private static let account = AppBrand.keychainAccount

    public static func service(for provider: ProviderID) -> String {
        "com.tokentorch.vendor.\(provider.rawValue).oauth"
    }

    public static func load(provider: ProviderID) throws -> OAuthSession? {
        guard
            let json = try KeychainReader.readGenericPassword(
                service: service(for: provider),
                account: account
            )
        else {
            return nil
        }
        return try decodeSession(json)
    }

    public static func save(provider: ProviderID, session: OAuthSession) throws {
        let json = try encodeSession(session)
        try KeychainReader.saveGenericPassword(
            service: service(for: provider),
            account: account,
            value: json
        )
    }

    public static func delete(provider: ProviderID) throws {
        try KeychainReader.deleteGenericPassword(service: service(for: provider), account: account)
    }

    public static func isFresh(provider: ProviderID) throws -> Bool {
        guard let session = try load(provider: provider) else { return false }
        return VendorCredentialsReader.sessionIsUsable(session)
    }

    private struct StoredPayload: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int64?
        let accountID: String?
        let subscriptionType: String?
        let source: CredentialSource
    }

    private static func encodeSession(_ session: OAuthSession) throws -> String {
        let payload = StoredPayload(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt,
            accountID: session.accountID,
            subscriptionType: session.subscriptionType,
            source: session.source
        )
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TokenTorchError.message("Failed to encode vendor credential copy")
        }
        return json
    }

    private static func decodeSession(_ json: String) throws -> OAuthSession {
        let data = Data(json.utf8)
        let payload = try JSONDecoder().decode(StoredPayload.self, from: data)
        return OAuthSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: payload.expiresAt,
            accountID: payload.accountID,
            subscriptionType: payload.subscriptionType,
            source: payload.source
        )
    }
}

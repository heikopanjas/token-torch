import Foundation

public enum TokenTorchError: Error, LocalizedError, Sendable {
    case message(String)
    case claudeRepairFailed(String)
    case missingCredentials(String)
    case missingAdminKey(provider: ProviderID)
    case missingPersonalAccessToken(provider: ProviderID)
    case needsAuthorization(provider: ProviderID)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
            case .message(let text): text
            case .claudeRepairFailed(let text): text
            case .missingCredentials(let text): text
            case .missingAdminKey(let provider): "\(provider.displayName) admin key not configured in Token Torch Keychain settings."
            case .missingPersonalAccessToken(let provider):
                "\(provider.displayName) GitHub Personal Access Token not configured in Token Torch Keychain settings."
            case .needsAuthorization(let provider):
                "\(provider.displayName) needs authorization. Click Refresh to allow Keychain access, or log in with the vendor app."
            case .unsupported(let text): text
        }
    }
}

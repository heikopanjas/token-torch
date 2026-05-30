import Foundation

public enum TokenTorchError: Error, LocalizedError, Sendable {
    case message(String)
    case missingCredentials(String)
    case missingAdminKey(provider: ProviderID)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
            case .message(let text): text
            case .missingCredentials(let text): text
            case .missingAdminKey(let provider): "\(provider.displayName) admin key not configured in Token Torch Keychain settings."
            case .unsupported(let text): text
        }
    }
}

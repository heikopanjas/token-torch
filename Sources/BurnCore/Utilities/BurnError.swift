import Foundation

public enum BurnError: Error, LocalizedError, Sendable {
    case message(String)
    case missingCredentials(String)
    case missingAdminKey(provider: ProviderID)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
            case .message(let text): text
            case .missingCredentials(let text): text
            case .missingAdminKey(let provider): "\(provider.displayName) admin key not configured in burn Keychain settings."
            case .unsupported(let text): text
        }
    }
}

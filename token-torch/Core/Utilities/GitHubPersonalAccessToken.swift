import Foundation

/// Classification and validation for GitHub tokens used with Copilot quota APIs.
public enum GitHubPersonalAccessToken: Sendable, Equatable {
    case classic
    case fineGrained
    case oauth
    case unknown(String)

    public static func classify(_ token: String) -> GitHubPersonalAccessToken {
        if token.hasPrefix("ghp_") || token.hasPrefix("gho_") { return .classic }
        if token.hasPrefix("github_pat_") { return .fineGrained }
        if token.hasPrefix("ghu_") { return .oauth }
        let prefix = token.prefix(while: { $0.isLetter || $0 == "_" })
        return .unknown(String(prefix.isEmpty ? "?" : prefix))
    }

    public static func normalize(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// GitHub Copilot internal endpoints reject classic PATs and require a fine-grained token
    /// with the account **Copilot requests** permission (see GitHub Copilot CLI auth docs).
    public static func validateForCopilot(_ token: String) throws -> String {
        let normalized = normalize(token)
        guard normalized.isEmpty == false else {
            throw TokenTorchError.message("GitHub Personal Access Token is empty.")
        }
        switch classify(normalized) {
            case .classic:
                throw TokenTorchError.message(
                    """
                    Classic GitHub PATs (ghp_…) are not accepted by the Copilot usage API. \
                    Create a fine-grained personal access token on your personal account with \
                    Account permission “Copilot requests” (Read-only), then paste it in Settings. \
                    Classic tokens with read:user still return HTTP 401.
                    """
                )
            case .fineGrained, .oauth:
                return normalized
            case .unknown(let prefix):
                throw TokenTorchError.message(
                    "Unrecognized GitHub token prefix (\(prefix)…). Expected a fine-grained PAT (github_pat_…)."
                )
        }
    }

    public static func redactedSummary(_ token: String) -> String {
        let normalized = normalize(token)
        guard normalized.isEmpty == false else { return "empty" }
        let kind: String = switch classify(normalized) {
            case .classic: "classic"
            case .fineGrained: "fine-grained"
            case .oauth: "oauth"
            case .unknown: "unknown"
        }
        let prefix = String(normalized.prefix(4))
        return "\(kind) len=\(normalized.count) prefix=\(prefix)…"
    }
}

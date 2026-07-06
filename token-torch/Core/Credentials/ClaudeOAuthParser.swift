import Foundation

enum ClaudeOAuthParser {
    private struct ClaudeCredentialsFile: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Int64?
            let subscriptionType: String?
            let rateLimitTier: String?

            enum CodingKeys: String, CodingKey {
                case accessToken, refreshToken, expiresAt, subscriptionType, rateLimitTier
            }
        }

        let oauth: OAuth

        enum CodingKeys: String, CodingKey {
            case oauth = "claudeAiOauth"
        }
    }

    static func parse(_ json: String, source: CredentialSource) throws -> OAuthSession {
        let data = Data(json.utf8)
        let parsed = try JSONDecoder().decode(ClaudeCredentialsFile.self, from: data)
        return OAuthSession(
            accessToken: parsed.oauth.accessToken,
            refreshToken: parsed.oauth.refreshToken,
            expiresAt: parsed.oauth.expiresAt,
            accountID: nil,
            subscriptionType: parsed.oauth.subscriptionType,
            rateLimitTier: parsed.oauth.rateLimitTier,
            source: source
        )
    }
}

import Foundation

public enum Redaction {
    private static let patterns = [
        "Bearer ", "bearer ", "access_token", "refresh_token", "accessToken", "refreshToken"
    ]

    private static let prefixes = [
        "github_pat_", "ghp_", "ghu_", "gho_", "eyJhbG", "eyJ", "sk-ant-admin-", "sk-admin-", "sk-ant-api-", "sk-ant-", "sk-proj-", "sk-"
    ]

    public static func redactSecrets(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            result = redactAfterPattern(result, pattern: pattern)
        }
        for prefix in prefixes {
            result = redactTokenPrefix(result, prefix: prefix)
        }
        return result
    }

    private static func isTokenDelimiter(_ ch: Character) -> Bool {
        ch.isWhitespace || ch == "\"" || ch == "'" || ch == ")" || ch == "]" || ch == ","
    }

    private static func tokenEnd(_ text: Substring) -> Int {
        for (index, ch) in text.enumerated() where isTokenDelimiter(ch) {
            return index
        }
        return text.count
    }

    private static func redactAfterPattern(_ text: String, pattern: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let range = rest.range(of: pattern) {
            out += rest[..<range.upperBound]
            out += "[REDACTED]"
            let after = rest[range.upperBound...]
            let skip = tokenEnd(after)
            rest = after.dropFirst(skip)
        }
        out += rest
        return out
    }

    private static func redactTokenPrefix(_ text: String, prefix: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let range = rest.range(of: prefix) {
            out += rest[..<range.lowerBound]
            out += "[REDACTED]"
            let after = rest[range.upperBound...]
            let skip = tokenEnd(after)
            rest = after.dropFirst(skip)
        }
        out += rest
        return out
    }
}

import CryptoKit
import Foundation

enum ClaudeCredentialPaths {
    static let defaultKeychainService = "Claude Code-credentials"

    static func configDirs() -> [URL] {
        var dirs: [URL] = []
        if let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            dirs.append(URL(fileURLWithPath: config))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.append(home.appendingPathComponent(".config/claude"))
        dirs.append(home.appendingPathComponent(".claude"))
        var seen = Set<String>()
        return dirs.filter { seen.insert($0.path).inserted }
    }

    static func keychainServices(defaultService: String = defaultKeychainService) -> [String] {
        var services: [String] = []
        for dir in Self.configDirs() {
            let hash = SHA256.hash(data: Data(dir.path.utf8))
            let hex = hash.map { String(format: "%02x", $0) }.joined()
            services.append("Claude Code-credentials-\(String(hex.prefix(8)))")
        }
        services.append(defaultService)
        var seen = Set<String>()
        return services.filter { seen.insert($0).inserted }
    }

    static func credentialPaths() -> [URL] {
        return Self.configDirs().map { $0.appendingPathComponent(".credentials.json") }
    }
}

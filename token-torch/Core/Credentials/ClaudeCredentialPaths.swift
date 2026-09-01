import CryptoKit
import Foundation

enum ClaudeCredentialPaths {
    static let defaultKeychainService = "Claude Code-credentials"

    static func defaultConfigDir() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    static func preferredDefaultConfigDir() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configClaude = home.appendingPathComponent(".config/claude")
        if FileManager.default.fileExists(atPath: configClaude.path) == true {
            return configClaude
        }
        return Self.defaultConfigDir()
    }

    static func configDirs(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var dirs: [URL] = []
        if let config = environment["CLAUDE_CONFIG_DIR"], config.isEmpty == false {
            dirs.append(URL(fileURLWithPath: config))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.append(home.appendingPathComponent(".config/claude"))
        dirs.append(home.appendingPathComponent(".claude"))
        var seen = Set<String>()
        return dirs.filter { seen.insert($0.path).inserted }
    }

    static func keychainService(forConfigDir directory: URL) -> String {
        let hash = SHA256.hash(data: Data(directory.path.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(String(hex.prefix(8)))"
    }

    static func keychainServices(
        defaultService: String = defaultKeychainService,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        var services = Self.configDirs(environment: environment).map(Self.keychainService(forConfigDir:))
        services.append(defaultService)
        var seen = Set<String>()
        return services.filter { seen.insert($0).inserted }
    }

    static func credentialPaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        return Self.configDirs(environment: environment).map { $0.appendingPathComponent(".credentials.json") }
    }

    static func configDir(
        forKeychainService service: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if service == Self.defaultKeychainService {
            return Self.defaultConfigDir()
        }
        for directory in Self.configDirs(environment: environment) where Self.keychainService(forConfigDir: directory) == service {
            return directory
        }
        return nil
    }

    static func configDir(
        for source: CredentialSource,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        switch source {
            case .claudeKeychain(let service):
                return Self.configDir(forKeychainService: service, environment: environment)
            case .claudeFile(let url):
                return url.deletingLastPathComponent()
            case .codexFile, .codexKeychain, .cursorSqlite, .cursorKeychain, .tokenTorchCopy:
                return nil
        }
    }
}

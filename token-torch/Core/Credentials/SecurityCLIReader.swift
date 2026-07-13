import Foundation

enum SecurityCLIReader {
    private static let executablePath = "/usr/bin/security"
    private static let itemNotFoundStatus: Int32 = 44

    static let automaticTimeout: TimeInterval = 1.5
    static let interactiveTimeout: TimeInterval = 30

    static func readGenericPassword(
        service: String,
        account: String? = nil,
        timeout: TimeInterval = automaticTimeout
    ) async throws -> String? {
        let result = try await ProcessRunner.run(
            executablePath: Self.executablePath,
            arguments: Self.arguments(service: service, account: account),
            timeout: timeout
        )
        return try Self.password(from: result, service: service)
    }

    static func readAllGenericPasswords(service: String, timeout: TimeInterval = automaticTimeout) async throws -> [String] {
        try Task.checkCancellation()
        let accounts = KeychainReader.genericPasswordMetadata(service: service)
            .items
            .compactMap(\.account)
            .filter { $0.isEmpty == false }
        let uniqueAccounts = Array(Set(accounts)).sorted()

        if uniqueAccounts.isEmpty == true {
            do {
                if let password = try await Self.readGenericPassword(service: service, timeout: timeout) {
                    return [password]
                }
            }
            catch is CancellationError {
                throw CancellationError()
            }
            catch {
                return []
            }
            return []
        }

        var passwords: [String] = []
        for account in uniqueAccounts {
            try Task.checkCancellation()
            do {
                if let password = try await Self.readGenericPassword(service: service, account: account, timeout: timeout) {
                    passwords.append(password)
                }
            }
            catch is CancellationError {
                throw CancellationError()
            }
            catch {
                continue
            }
        }
        return passwords
    }

    static func timeout(interactive: Bool) -> TimeInterval {
        return interactive == true ? Self.interactiveTimeout : Self.automaticTimeout
    }

    static func arguments(service: String, account: String?) -> [String] {
        var arguments = ["find-generic-password", "-s", service]
        if let account, account.isEmpty == false {
            arguments.append(contentsOf: ["-a", account])
        }
        arguments.append("-w")
        return arguments
    }

    static func password(from result: ProcessRunner.Result, service: String) throws -> String? {
        if result.terminationStatus == Self.itemNotFoundStatus {
            return nil
        }
        guard result.terminationStatus == 0 else {
            throw TokenTorchError.message(
                "security could not read Keychain item \"\(service)\" (status \(result.terminationStatus))."
            )
        }

        let value = String(data: result.standardOutput, encoding: .utf8) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

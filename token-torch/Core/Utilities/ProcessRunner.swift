import Darwin
import Foundation

enum ProcessRunner {
    struct Result: Sendable {
        let standardOutput: Data
        let standardError: Data
        let terminationStatus: Int32
    }

    enum Failure: LocalizedError {
        case launchFailed(executablePath: String, message: String)
        case timedOut(commandName: String)

        var errorDescription: String? {
            switch self {
                case .launchFailed(let executablePath, let message):
                    return "Failed to launch \(executablePath): \(message)"
                case .timedOut(let commandName):
                    return "\(commandName) timed out."
            }
        }
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let condition = NSCondition()
        private let limit: Int
        private var data = Data()
        private var reachedEndOfFile = false

        init(limit: Int) {
            self.limit = limit
        }

        func append(_ newData: Data) -> Void {
            self.condition.lock()
            defer {
                self.condition.broadcast()
                self.condition.unlock()
            }
            if newData.isEmpty == true {
                self.reachedEndOfFile = true
                return
            }
            let remaining = max(0, self.limit - self.data.count)
            if remaining > 0 {
                self.data.append(newData.prefix(remaining))
            }
        }

        func waitForEndOfFile(timeout: TimeInterval) -> Void {
            self.condition.lock()
            defer { self.condition.unlock() }
            let deadline = Date().addingTimeInterval(timeout)
            while self.reachedEndOfFile == false, self.condition.wait(until: deadline) == true {}
        }

        func snapshot() -> Data {
            self.condition.lock()
            defer { self.condition.unlock() }
            return self.data
        }
    }

    private final class CStringArray {
        private(set) var pointers: [UnsafeMutablePointer<CChar>?]

        init(_ strings: [String]) {
            self.pointers = strings.map { strdup($0) } + [nil]
        }

        func withUnsafeMutableBufferPointer<Result>(
            _ body: (UnsafeMutableBufferPointer<UnsafeMutablePointer<CChar>?>) throws -> Result
        ) rethrows -> Result {
            return try self.pointers.withUnsafeMutableBufferPointer { buffer in
                return try body(buffer)
            }
        }

        deinit {
            for pointer in self.pointers {
                free(pointer)
            }
        }
    }

    private static let pollInterval: TimeInterval = 0.02
    private static let terminationGracePeriod: TimeInterval = 0.4
    private static let outputDrainTimeout: TimeInterval = 1
    private static let defaultOutputLimit = 1_048_576

    static func run(
        executablePath: String,
        arguments: [String],
        input: Data? = nil,
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        outputLimit: Int = defaultOutputLimit
    ) async throws -> Result {
        let task = Task.detached(priority: .utility) {
            return try Self.runSynchronously(
                executablePath: executablePath,
                arguments: arguments,
                input: input,
                timeout: timeout,
                environment: environment,
                workingDirectory: workingDirectory,
                outputLimit: outputLimit
            )
        }
        return try await withTaskCancellationHandler {
            return try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func runSynchronously(
        executablePath: String,
        arguments: [String],
        input: Data?,
        timeout: TimeInterval,
        environment: [String: String]?,
        workingDirectory: URL?,
        outputLimit: Int
    ) throws -> Result {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = input == nil ? nil : Pipe()
        let outputBuffer = OutputBuffer(limit: outputLimit)
        let errorBuffer = OutputBuffer(limit: outputLimit)
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }

        let pid: pid_t
        do {
            pid = try Self.spawn(
                executablePath: executablePath,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory,
                outputPipe: outputPipe,
                errorPipe: errorPipe,
                inputPipe: inputPipe
            )
        }
        catch {
            Self.closePipes(outputPipe: outputPipe, errorPipe: errorPipe, inputPipe: inputPipe)
            throw error
        }

        if let input, let inputPipe {
            try? inputPipe.fileHandleForReading.close()
            try? inputPipe.fileHandleForWriting.write(contentsOf: input)
            try? inputPipe.fileHandleForWriting.close()
        }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()

        let terminationStatus: Int32
        do {
            terminationStatus = try Self.waitForExit(pid: pid, timeout: timeout, executablePath: executablePath)
        }
        catch {
            Self.finishReading(
                outputPipe: outputPipe,
                errorPipe: errorPipe,
                outputBuffer: outputBuffer,
                errorBuffer: errorBuffer
            )
            throw error
        }

        Self.finishReading(
            outputPipe: outputPipe,
            errorPipe: errorPipe,
            outputBuffer: outputBuffer,
            errorBuffer: errorBuffer
        )
        return Result(
            standardOutput: outputBuffer.snapshot(),
            standardError: errorBuffer.snapshot(),
            terminationStatus: terminationStatus
        )
    }

    private static func spawn(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?,
        outputPipe: Pipe,
        errorPipe: Pipe,
        inputPipe: Pipe?
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw Failure.launchFailed(executablePath: executablePath, message: "Could not initialize process attributes.")
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw Failure.launchFailed(executablePath: executablePath, message: "Could not initialize process attributes.")
        }
        defer { posix_spawnattr_destroy(&attributes) }

        let outputRead = outputPipe.fileHandleForReading.fileDescriptor
        let outputWrite = outputPipe.fileHandleForWriting.fileDescriptor
        let errorRead = errorPipe.fileHandleForReading.fileDescriptor
        let errorWrite = errorPipe.fileHandleForWriting.fileDescriptor
        var actionStatus = posix_spawn_file_actions_addclose(&fileActions, outputRead)
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_adddup2(&fileActions, outputWrite, STDOUT_FILENO)
        }
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_addclose(&fileActions, outputWrite)
        }
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_addclose(&fileActions, errorRead)
        }
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_adddup2(&fileActions, errorWrite, STDERR_FILENO)
        }
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_addclose(&fileActions, errorWrite)
        }
        if let inputPipe, actionStatus == 0 {
            let inputRead = inputPipe.fileHandleForReading.fileDescriptor
            let inputWrite = inputPipe.fileHandleForWriting.fileDescriptor
            actionStatus = posix_spawn_file_actions_addclose(&fileActions, inputWrite)
            if actionStatus == 0 {
                actionStatus = posix_spawn_file_actions_adddup2(&fileActions, inputRead, STDIN_FILENO)
            }
            if actionStatus == 0 {
                actionStatus = posix_spawn_file_actions_addclose(&fileActions, inputRead)
            }
        }
        if let workingDirectory, actionStatus == 0 {
            actionStatus = workingDirectory.path.withCString {
                return posix_spawn_file_actions_addchdir_np(&fileActions, $0)
            }
        }
        guard actionStatus == 0 else {
            throw Failure.launchFailed(
                executablePath: executablePath,
                message: Self.errorMessage(code: actionStatus)
            )
        }

        let spawnFlags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
        var attributeStatus = posix_spawnattr_setflags(&attributes, Int16(spawnFlags))
        if attributeStatus == 0 {
            attributeStatus = posix_spawnattr_setpgroup(&attributes, 0)
        }
        guard attributeStatus == 0 else {
            throw Failure.launchFailed(
                executablePath: executablePath,
                message: Self.errorMessage(code: attributeStatus)
            )
        }

        let argv = CStringArray([executablePath] + arguments)
        let environmentValues = environment ?? ProcessInfo.processInfo.environment
        let environmentStrings = environmentValues.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let environmentPointers = CStringArray(environmentStrings)
        var pid: pid_t = 0
        let spawnStatus = executablePath.withCString { path in
            return argv.withUnsafeMutableBufferPointer { argvBuffer in
                return environmentPointers.withUnsafeMutableBufferPointer { environmentBuffer in
                    return posix_spawn(
                        &pid,
                        path,
                        &fileActions,
                        &attributes,
                        argvBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }
        guard spawnStatus == 0 else {
            throw Failure.launchFailed(
                executablePath: executablePath,
                message: Self.errorMessage(code: spawnStatus)
            )
        }
        return pid
    }

    private static func waitForExit(pid: pid_t, timeout: TimeInterval, executablePath: String) throws -> Int32 {
        let deadline = Date().addingTimeInterval(timeout)
        while true == true {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                return Self.terminationStatus(waitStatus: status)
            }
            if result == -1, errno != EINTR {
                throw Failure.launchFailed(
                    executablePath: executablePath,
                    message: Self.errorMessage(code: errno)
                )
            }
            if Task.isCancelled == true {
                Self.terminateAndReap(pid: pid)
                throw CancellationError()
            }
            if Date() >= deadline {
                Self.terminateAndReap(pid: pid)
                throw Failure.timedOut(commandName: URL(fileURLWithPath: executablePath).lastPathComponent)
            }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
    }

    private static func finishReading(
        outputPipe: Pipe,
        errorPipe: Pipe,
        outputBuffer: OutputBuffer,
        errorBuffer: OutputBuffer
    ) -> Void {
        outputBuffer.waitForEndOfFile(timeout: Self.outputDrainTimeout)
        errorBuffer.waitForEndOfFile(timeout: Self.outputDrainTimeout)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
    }

    private static func closePipes(outputPipe: Pipe, errorPipe: Pipe, inputPipe: Pipe?) -> Void {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        if let inputPipe {
            try? inputPipe.fileHandleForWriting.close()
            try? inputPipe.fileHandleForReading.close()
        }
    }

    private static func terminateAndReap(pid: pid_t) -> Void {
        kill(-pid, SIGTERM)
        kill(pid, SIGTERM)
        var reaped = false
        let deadline = Date().addingTimeInterval(Self.terminationGracePeriod)
        while Date() < deadline {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) {
                reaped = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        kill(-pid, SIGKILL)
        kill(pid, SIGKILL)
        while reaped == false {
            var status: Int32 = 0
            let result = waitpid(pid, &status, 0)
            if result == pid || (result == -1 && errno == ECHILD) {
                reaped = true
            }
            else if result == -1, errno != EINTR {
                reaped = true
            }
        }
    }

    private static func terminationStatus(waitStatus: Int32) -> Int32 {
        let signal = waitStatus & 0x7F
        if signal == 0 {
            return (waitStatus >> 8) & 0xFF
        }
        return 128 + signal
    }

    private static func errorMessage(code: Int32) -> String {
        guard let message = strerror(code) else {
            return "POSIX error \(code)."
        }
        return String(cString: message)
    }
}

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
    private static let defaultPseudoTerminalColumns: UInt16 = 120
    private static let defaultPseudoTerminalRows: UInt16 = 40
    private static let defaultTerminalType = "xterm-256color"

    static func run(
        executablePath: String,
        arguments: [String],
        input: Data? = nil,
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        outputLimit: Int = defaultOutputLimit
    ) async throws -> Result {
        return try await Self.runDetached {
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
    }

    /// Runs a process with stdin/stdout/stderr attached to a pseudo-terminal replica.
    /// Merged terminal output is returned in `standardOutput`; `standardError` is empty.
    static func runInPseudoTerminal(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        outputLimit: Int = defaultOutputLimit,
        columns: UInt16 = defaultPseudoTerminalColumns,
        rows: UInt16 = defaultPseudoTerminalRows
    ) async throws -> Result {
        return try await Self.runDetached {
            return try Self.runInPseudoTerminalSynchronously(
                executablePath: executablePath,
                arguments: arguments,
                timeout: timeout,
                environment: environment,
                workingDirectory: workingDirectory,
                outputLimit: outputLimit,
                columns: columns,
                rows: rows
            )
        }
    }

    private static func runDetached(_ body: @escaping @Sendable () throws -> Result) async throws -> Result {
        let task = Task.detached(priority: .utility) {
            return try body()
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

    private static func runInPseudoTerminalSynchronously(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        environment: [String: String]?,
        workingDirectory: URL?,
        outputLimit: Int,
        columns: UInt16,
        rows: UInt16
    ) throws -> Result {
        var primaryFD: Int32 = -1
        var replicaFD: Int32 = -1
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &replicaFD, nil, nil, &size) == 0 else {
            throw Failure.launchFailed(
                executablePath: executablePath,
                message: "Could not allocate a pseudo-terminal (\(Self.errorMessage(code: errno)))."
            )
        }

        let outputBuffer = OutputBuffer(limit: outputLimit)
        let pid: pid_t
        do {
            pid = try Self.spawnInPseudoTerminal(
                executablePath: executablePath,
                arguments: arguments,
                environment: Self.environmentForPseudoTerminal(environment),
                workingDirectory: workingDirectory,
                primaryFD: primaryFD,
                replicaFD: replicaFD
            )
        }
        catch {
            close(primaryFD)
            close(replicaFD)
            throw error
        }

        // Child owns the replica; closing the parent copy lets master reads finish after exit.
        close(replicaFD)
        Self.startPseudoTerminalReader(primaryFD: primaryFD, buffer: outputBuffer)

        let terminationStatus: Int32
        do {
            terminationStatus = try Self.waitForExit(pid: pid, timeout: timeout, executablePath: executablePath)
        }
        catch {
            close(primaryFD)
            outputBuffer.waitForEndOfFile(timeout: Self.outputDrainTimeout)
            throw error
        }

        close(primaryFD)
        outputBuffer.waitForEndOfFile(timeout: Self.outputDrainTimeout)
        return Result(
            standardOutput: outputBuffer.snapshot(),
            standardError: Data(),
            terminationStatus: terminationStatus
        )
    }

    private static func environmentForPseudoTerminal(_ environment: [String: String]?) -> [String: String] {
        var values = environment ?? ProcessInfo.processInfo.environment
        if values["TERM"] == nil || values["TERM"]?.isEmpty == true {
            values["TERM"] = Self.defaultTerminalType
        }
        return values
    }

    private static func startPseudoTerminalReader(primaryFD: Int32, buffer: OutputBuffer) -> Void {
        let thread = Thread {
            var chunk = [UInt8](repeating: 0, count: 4_096)
            while true == true {
                let bytesRead = chunk.withUnsafeMutableBufferPointer { pointer in
                    return read(primaryFD, pointer.baseAddress, pointer.count)
                }
                if bytesRead > 0 {
                    buffer.append(Data(chunk[0 ..< bytesRead]))
                    continue
                }
                if bytesRead == 0 {
                    buffer.append(Data())
                    return
                }
                if errno == EINTR {
                    continue
                }
                // EIO is the expected signal that the child closed the PTY replica.
                buffer.append(Data())
                return
            }
        }
        thread.qualityOfService = .utility
        thread.start()
    }

    private static func spawnInPseudoTerminal(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        primaryFD: Int32,
        replicaFD: Int32
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

        var actionStatus = posix_spawn_file_actions_adddup2(&fileActions, replicaFD, STDIN_FILENO)
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_adddup2(&fileActions, replicaFD, STDOUT_FILENO)
        }
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_adddup2(&fileActions, replicaFD, STDERR_FILENO)
        }
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_addclose(&fileActions, primaryFD)
        }
        if actionStatus == 0 {
            actionStatus = posix_spawn_file_actions_addclose(&fileActions, replicaFD)
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

        try Self.applyProcessGroupAttributes(&attributes, executablePath: executablePath)
        return try Self.posixSpawn(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            fileActions: &fileActions,
            attributes: &attributes
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

        try Self.applyProcessGroupAttributes(&attributes, executablePath: executablePath)
        return try Self.posixSpawn(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment ?? ProcessInfo.processInfo.environment,
            fileActions: &fileActions,
            attributes: &attributes
        )
    }

    private static func applyProcessGroupAttributes(
        _ attributes: inout posix_spawnattr_t?,
        executablePath: String
    ) throws -> Void {
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
    }

    private static func posixSpawn(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        fileActions: inout posix_spawn_file_actions_t?,
        attributes: inout posix_spawnattr_t?
    ) throws -> pid_t {
        let argv = CStringArray([executablePath] + arguments)
        let environmentStrings = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
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

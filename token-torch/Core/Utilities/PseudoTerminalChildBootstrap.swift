import Darwin
import Foundation

/// Trampoline used by `ProcessRunner.runInPseudoTerminal` so a GUI-launched child can become
/// a session leader with a controlling terminal before executing the real command.
enum PseudoTerminalChildBootstrap {
    static let invocationArgument = "--token-torch-pty-child"

    /// If this process was launched as the PTY trampoline, assign the controlling terminal and
    /// replace the process with the requested command. Returns normally when not requested.
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Void {
        guard let markerIndex = arguments.firstIndex(of: Self.invocationArgument) else {
            return
        }
        let command = Array(arguments.suffix(from: markerIndex + 1))
        guard command.isEmpty == false else {
            FileHandle.standardError.write(Data("Token Torch PTY child: missing command.\n".utf8))
            exit(1)
        }
        Self.becomeControllingTerminalLeader()
        Self.exec(command: command)
    }

    private static func becomeControllingTerminalLeader() -> Void {
        _ = ioctl(STDIN_FILENO, TIOCSCTTY, 0)
        let group = getpgrp()
        _ = tcsetpgrp(STDIN_FILENO, group)
    }

    private static func exec(command: [String]) -> Never {
        guard let executable = command.first else {
            FileHandle.standardError.write(Data("Token Torch PTY child: missing executable.\n".utf8))
            exit(1)
        }
        let argv = CStringArray(command)
        executable.withCString { path in
            argv.withUnsafeMutableBufferPointer { buffer in
                _ = execvp(path, buffer.baseAddress)
            }
        }
        let message = String(cString: strerror(errno))
        FileHandle.standardError.write(Data("Token Torch PTY child: \(message)\n".utf8))
        exit(1)
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
}

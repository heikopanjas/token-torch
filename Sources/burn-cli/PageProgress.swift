import Foundation

final class PageProgress: @unchecked Sendable {
    private let enabled: Bool
    private var active = false
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    init(enabled: Bool = isatty(fileno(stderr)) != 0) {
        self.enabled = enabled
    }

    func update(page: Int) {
        guard enabled else { return }
        active = true
        let frame = frames[max(page - 1, 0) % frames.count]
        let line = "\r\(frame) Fetching..."
        FileHandle.standardError.write(Data(line.utf8))
    }

    func finish() {
        guard enabled else { return }
        active = false
        clearLine()
    }

    deinit {
        if enabled, active { clearLine() }
    }

    private func clearLine() {
        FileHandle.standardError.write(Data("\r\u{001B}[2K".utf8))
    }
}

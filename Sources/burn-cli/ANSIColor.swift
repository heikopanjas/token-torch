import Foundation

enum ANSIColor {
    static let reset = "\u{001B}[0m"

    static func brightBlueBold(_ text: String) -> String { wrap(text, codes: ["1", "94"]) }
    static func brightGreenBold(_ text: String) -> String { wrap(text, codes: ["1", "92"]) }
    static func brightYellowBold(_ text: String) -> String { wrap(text, codes: ["1", "93"]) }
    static func brightCyan(_ text: String) -> String { wrap(text, codes: ["96"]) }
    static func brightWhiteBold(_ text: String) -> String { wrap(text, codes: ["1", "97"]) }
    static func brightWhite(_ text: String) -> String { wrap(text, codes: ["97"]) }
    static func brightCyanLabel(_ text: String) -> String { wrap(text, codes: ["96"]) }
    static func yellow(_ text: String) -> String { wrap(text, codes: ["33"]) }
    static func redBold(_ text: String) -> String { wrap(text, codes: ["1", "31"]) }
    static func greenBold(_ text: String) -> String { wrap(text, codes: ["1", "32"]) }
    static func dimmed(_ text: String) -> String { wrap(text, codes: ["2"]) }

    static var useColors: Bool {
        if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
        return isatty(fileno(stderr)) != 0 || isatty(fileno(stdout)) != 0
    }

    static func styled(_ text: String, apply: (String) -> String) -> String {
        useColors ? apply(text) + reset : text
    }

    private static func wrap(_ text: String, codes: [String]) -> String {
        styled(text) { value in "\u{001B}[\(codes.joined(separator: ";"))m\(value)" }
    }
}

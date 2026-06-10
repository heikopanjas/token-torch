import Foundation

/// User-selectable menu bar status icon (org/platform brands, not subscription captions).
public enum MenuBarIconProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case anthropic
    case openai
    case cursor
    case copilot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .anthropic: "Anthropic"
            case .openai: "OpenAI"
            case .cursor: "Cursor"
            case .copilot: "Copilot"
        }
    }

    /// PDF basename in the app bundle (without extension).
    public var pdfResourceName: String {
        switch self {
            case .anthropic: "anthropic"
            case .openai: "openai"
            case .cursor: "cursor"
            case .copilot: "githubcopilot"
        }
    }
}

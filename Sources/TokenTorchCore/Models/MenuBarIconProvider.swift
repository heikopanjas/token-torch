import Foundation

/// User-selectable menu bar status icon (org/platform brands, not subscription captions).
public enum MenuBarIconProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Follows the first row of the General-tab Providers table (`ProviderPreferences.orderedSections()`).
    case topOfProviderList
    case anthropic
    case claudeCode
    case codex
    case openai
    case cursor
    case copilot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
            case .topOfProviderList: "<automatic>"
            case .anthropic: "Anthropic"
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .openai: "OpenAI"
            case .cursor: "Cursor"
            case .copilot: "Copilot"
        }
    }

    /// PDF basename in the app bundle (without extension). Nil for `topOfProviderList` (resolved from prefs).
    public var pdfResourceName: String? {
        switch self {
            case .topOfProviderList: nil
            case .anthropic: "anthropic"
            case .claudeCode: "claude"
            case .codex: "codex"
            case .openai: "openai"
            case .cursor: "cursor"
            case .copilot: "githubcopilot"
        }
    }
}

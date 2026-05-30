import Foundation

enum ScopeFormatting {
    static func formatEndLabel(_ end: String?) -> String {
        end ?? "present"
    }

    static func formatFetchBanner(scope: String, start: String, end: String?) -> String {
        "Fetching usage for \(scope) from \(start) to \(formatEndLabel(end))..."
    }

    static func formatWorkspaceFetchBanner(workspaceID: String, start: String, end: String?) -> String {
        "Fetching workspace usage for \(workspaceID) from \(start) to \(formatEndLabel(end))..."
    }
}

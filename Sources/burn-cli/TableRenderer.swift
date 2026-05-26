import BurnCore
import Foundation

enum TableRenderer {
    private static let usageHeaders = [
        "Period", "Workspace", "Model", "Input Tokens", "Output Tokens", "Cache Creation", "Cache Read", "Total Tokens"
    ]
    private static let openAIUsageHeaders = [
        "Workspace", "Model", "Input Tokens", "Output Tokens", "Cached Input", "Total Tokens", "Period"
    ]
    private static let workspaceHeaders = [
        "ID", "Name", "Created", "Archived", "Color", "Storage Geo", "Default Inference", "Allowed Inference", "Tags"
    ]
    private static let projectHeaders = ["ID", "Name", "Created", "Status"]

    static func renderUsageTable(_ rows: [OrgUsageRow]) -> String {
        let data = rows.map { row in
            [
                row.timePeriod,
                ScopeFilter.displayWorkspace(row.workspaceID),
                ScopeFilter.displayModel(row.model),
                String(row.inputTokens),
                String(row.outputTokens),
                String(row.cacheCreationTokens),
                String(row.cacheReadTokens),
                String(row.totalTokens)
            ]
        }
        return renderTable(headers: usageHeaders, rows: data)
    }

    static func renderOpenAIUsageTable(_ rows: [OrgUsageRow]) -> String {
        let data = rows.map { row in
            [
                ScopeFilter.displayWorkspace(row.workspaceID),
                ScopeFilter.displayModel(row.model),
                String(row.inputTokens),
                String(row.outputTokens),
                String(row.cacheReadTokens),
                String(row.totalTokens),
                row.timePeriod
            ]
        }
        return renderTable(headers: openAIUsageHeaders, rows: data)
    }

    static func renderWorkspacesTable(_ workspaces: [AnthropicWorkspace]) -> String {
        let data = workspaces.map { workspace in
            let residency = workspace.dataResidency
            return [
                workspace.id,
                workspace.name,
                DateRange.rfc3339DatePart(workspace.createdAt),
                workspace.archivedAt.map { DateRange.rfc3339DatePart($0) } ?? "—",
                workspace.displayColor ?? "—",
                residency?.workspaceGeo ?? "—",
                residency?.defaultInferenceGeo ?? "—",
                residency?.allowedGeosDisplay() ?? "—",
                workspace.tagsDisplay()
            ]
        }
        return renderTable(headers: workspaceHeaders, rows: data)
    }

    static func renderOpenAIProjectsTable(_ projects: [OpenAIProject]) -> String {
        let data = projects.map { project in
            [
                project.id,
                project.name ?? "—",
                formatUnixDate(project.createdAt),
                project.status ?? "—"
            ]
        }
        return renderTable(headers: projectHeaders, rows: data)
    }

    private static func formatUnixDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func renderTable(headers: [String], rows: [[String]]) -> String {
        var widths = headers.map(\.count)
        for row in rows {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }

        var out = borderLine(widths: widths, left: "+", fill: "-", right: "+")
        out += "\n"
        out += dataLine(cells: headers, widths: widths)
        out += "\n"
        out += borderLine(widths: widths, left: "+", fill: "-", right: "+")
        out += "\n"
        for row in rows {
            out += dataLine(cells: row, widths: widths)
            out += "\n"
        }
        out += borderLine(widths: widths, left: "+", fill: "-", right: "+")
        return out
    }

    private static func borderLine(widths: [Int], left: Character, fill: Character, right: Character) -> String {
        var line = String(left)
        for (index, width) in widths.enumerated() {
            if index > 0 { line.append("+") }
            line.append(String(repeating: String(fill), count: width + 2))
        }
        line.append(right)
        return line
    }

    private static func dataLine(cells: [String], widths: [Int]) -> String {
        var line = "|"
        for (cell, width) in zip(cells, widths) {
            line += " "
            line += padded(cell, width: width)
            line += " |"
        }
        return line
    }

    private static func padded(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return text + String(repeating: " ", count: width - text.count)
    }
}

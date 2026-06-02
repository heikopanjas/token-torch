import AppKit
import TokenTorchCore

enum MenuBarStatusIcon {
    private static let side: CGFloat = 18

    static func image() -> NSImage? {
        if let pdf = pdfImage() {
            return pdf
        }
        guard
            let symbol = NSImage(
                systemSymbolName: "flame.fill",
                accessibilityDescription: AppBrand.displayName
            )
        else {
            return nil
        }
        symbol.size = NSSize(width: side, height: side)
        symbol.isTemplate = true
        return symbol
    }

    private static func pdfImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "cursor", withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        return image
    }
}

enum ProviderIcons {
    static func settingsToolbarImage(for provider: ProviderID) -> NSImage? {
        let name =
            switch provider {
                case .claude: "anthropic"
                case .codex: "openai"
                case .cursor: "cursor"
                case .copilot: "githubcopilot"
            }
        return pdfImage(named: name, side: SettingsStyle.toolbarIconPointSize)
    }

    static func resourceName(for provider: ProviderID, kind: ProviderSectionKind) -> String {
        switch provider {
            case .claude: kind == .subscription ? "claude" : "anthropic"
            case .codex: "openai"
            case .cursor: "cursor"
            case .copilot: "githubcopilot"
        }
    }

    static func resourceName(for provider: ProviderID, report: ProviderReport) -> String {
        resourceName(for: provider, kind: report.sectionKind)
    }

    static func image(for provider: ProviderID, report: ProviderReport) -> NSImage? {
        pdfImage(named: resourceName(for: provider, report: report), side: 18)
    }

    static func image(for section: ProviderSection, side: CGFloat = 18) -> NSImage? {
        pdfImage(named: resourceName(for: section.provider, kind: section.kind), side: side)
    }

    private static func pdfImage(named name: String, side: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: side, height: side)
        image.isTemplate = false
        return image
    }
}

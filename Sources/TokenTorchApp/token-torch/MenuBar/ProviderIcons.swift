import AppKit
import TokenTorchCore

enum ProviderIcons {
    static func settingsToolbarImage(for provider: ProviderID) -> NSImage? {
        let name =
            switch provider {
                case .claude: "anthropic"
                case .codex: "openai"
                case .cursor: "cursor"
                case .copilot: "githubcopilot"
            }
        return paddedToolbarImage(named: name)
    }

    /// Composites a provider logo PDF into a transparent square canvas wider
    /// than the toolbar's icon slot, with the logo aspect-fitted into a smaller
    /// centered box. The oversized canvas prevents the `.preference` toolbar
    /// from upscaling the image, so the logo displays at the SF Symbol size.
    private static func paddedToolbarImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
            let logo = NSImage(contentsOf: url)
        else {
            return nil
        }
        let canvas = SettingsStyle.toolbarProviderCanvasSide
        let box = SettingsStyle.toolbarProviderLogoBox
        let natural = logo.size
        let scale =
            natural.width > 0 && natural.height > 0
            ? min(box / natural.width, box / natural.height)
            : 1
        let drawn = NSSize(width: natural.width * scale, height: natural.height * scale)
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        logo.draw(
            in: NSRect(
                x: (canvas - drawn.width) / 2,
                y: (canvas - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func resourceName(for provider: ProviderID, kind: ProviderSectionKind) -> String {
        switch provider {
            case .claude: kind == .subscription ? "claude" : "anthropic"
            case .codex: "openai"
            case .cursor: "cursor"
            case .copilot: "githubcopilot"
        }
    }

    /// General-tab provider list and menu bar icon picker (including `<automatic>`).
    /// Claude Code / Codex subscription rows use `clawd.pdf` / `codex.pdf`; usage menu headers unchanged.
    static func generalSettingsResourceName(for provider: ProviderID, kind: ProviderSectionKind) -> String {
        if provider == .claude, kind == .subscription { return "clawd" }
        if provider == .codex, kind == .subscription { return "codex" }
        return resourceName(for: provider, kind: kind)
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

    static func generalSettingsImage(for section: ProviderSection, side: CGFloat = 18) -> NSImage? {
        pdfImage(named: generalSettingsResourceName(for: section.provider, kind: section.kind), side: side)
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

import AppKit

@MainActor
final class InfoSettingsViewController: SettingsPaneViewController {
    private var sectionLabel: NSTextField!
    private var hintLabel: NSTextField!
    private var refreshButton: NSButton!
    private var textView: NSTextView!

    override var paneHeight: CGFloat { SettingsStyle.infoPaneHeight }

    override func makeContentView() -> NSView {
        let w = SettingsStyle.paneWidth
        let h = self.paneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - SettingsStyle.contentPadding - 16

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        sectionLabel = NSTextField(labelWithString: "Current Vendor Credential Sources")
        sectionLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        sectionLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(sectionLabel)

        hintLabel = SettingsLayout.makeHintLabel(InfoSettingsCopy.vendorCredentialSourcesHint)
        let hintHeight = SettingsLayout.measuredHintHeight(hintLabel, width: controlW)
        y -= 4 + hintHeight
        hintLabel.frame = NSRect(x: x, y: y, width: controlW, height: hintHeight)
        content.addSubview(hintLabel)

        y -= SettingsLayout.groupedControlGap + 22
        refreshButton = NSButton(title: "Refresh Info", target: self, action: #selector(refreshInfo))
        refreshButton.bezelStyle = .rounded
        refreshButton.frame = NSRect(x: x, y: y, width: 110, height: 22)
        refreshButton.autoresizingMask = [.minYMargin]
        content.addSubview(refreshButton)

        y -= 16
        let scrollFrame = NSRect(x: x, y: SettingsStyle.contentPadding, width: controlW, height: max(y - SettingsStyle.contentPadding, 160))
        let scroll = NSScrollView(frame: scrollFrame)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        textView = NSTextView(frame: scroll.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView
        content.addSubview(scroll)

        return content
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshInfo()
    }

    @objc private func refreshInfo() {
        textView.string = Self.format(VendorCredentialsReader.vendorCredentialSourceInfo())
    }

    private static func format(_ sources: [VendorCredentialSourceInfo]) -> String {
        guard sources.isEmpty == false else {
            return """
                No enabled subscription provider currently has an imported Token Torch credential copy.

                Use Refresh or Reset subscription credentials on a provider tab to import credentials first.
                Secret values are not displayed.
                """
        }

        var lines: [String] = [
            "\(AppBrand.displayName) current vendor credential source metadata",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Secret values: not displayed",
            ""
        ]

        var currentProvider: ProviderID?
        for source in sources {
            if currentProvider != source.provider {
                currentProvider = source.provider
                lines.append(source.provider.displayName)
                lines.append(String(repeating: "-", count: source.provider.displayName.count))
            }

            lines.append("\(source.title)")
            lines.append("  Type: \(source.kind.rawValue)")
            lines.append("  Status: \(source.status)")
            for detail in source.details {
                lines.append("  \(detail.label): \(detail.value)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

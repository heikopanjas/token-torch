import AppKit

@MainActor
enum SettingsLayout {
    static let groupedControlGap: CGFloat = 8

    static func makeHintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.autoresizingMask = [.minYMargin, .width]
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        return label
    }

    static func measuredHintHeight(_ label: NSTextField, width: CGFloat) -> CGFloat {
        let size = label.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
        return max(ceil(size.height) + 4, 16)
    }
}

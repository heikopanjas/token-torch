import AppKit

@MainActor
enum UsageMenuItemViews {
    private static let inset: CGFloat = 12
    /// Space added below a row that has an attached caption, so the row+caption group reads as
    /// separate from the next item. Caption-less rows stay compact.
    private static let rowSpacing: CGFloat = 7
    private static let barHeight: CGFloat = 2
    private static let barBottomPad: CGFloat = 3
    private static let barTopGap: CGFloat = 3
    /// Vertical space a usage bar claims at the bottom of a row. It mostly fits inside the padding a
    /// row already reserves, so adding a bar barely changes row height and a row without one is
    /// laid out exactly as before.
    private static var barBand: CGFloat { Self.barBottomPad + Self.barHeight + Self.barTopGap }

    static func customItem(view: NSView, height: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        view.frame = NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: height)
        item.view = view
        item.isEnabled = false
        return item
    }

    static func header(result: AllProvidersResult?, isLoading: Bool) -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: 28))
        let text: String
        if isLoading == true {
            text = "Fetching data\u{2026}"
        }
        else if let result {
            text = "Updated \(result.fetchedAt.formatted(date: .omitted, time: .shortened))"
        }
        else {
            text = ""
        }
        if text.isEmpty == false {
            let label = labelField(text, font: MenuFormat.captionFont, color: .secondaryLabelColor)
            label.frame.origin = CGPoint(x: inset, y: 6)
            label.sizeToFit()
            container.addSubview(label)
        }
        if isLoading == true {
            let spinner = NSProgressIndicator(frame: NSRect(x: MenuFormat.menuWidth - inset - 14, y: 7, width: 14, height: 14))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            container.addSubview(spinner)
        }
        return customItem(view: container, height: 28)
    }

    static func caption(_ text: String) -> NSMenuItem {
        return Self.twoColumnRow(label: text, value: nil, valueColor: .secondaryLabelColor, font: MenuFormat.captionFont, height: 22)
    }

    static func boldRow(label: String, value: String) -> NSMenuItem {
        twoColumnRow(
            label: label,
            value: value,
            valueColor: .labelColor,
            font: MenuFormat.subheadlineBoldFont,
            height: 24
        )
    }

    /// `usedPercent` draws a 2px usage bar under the row; pass it only for a percentage of a cap.
    static func costRow(
        label: String,
        value: String,
        caption: String? = nil,
        usedPercent: Double? = nil
    ) -> NSMenuItem {
        twoColumnRow(
            label: label,
            value: value,
            valueColor: .labelColor,
            font: MenuFormat.costRowBoldFont,
            height: 22,
            caption: caption,
            usedPercent: usedPercent
        )
    }

    static func menuSpacer(height: CGFloat = 6) -> NSMenuItem {
        customItem(
            view: NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: height)),
            height: height
        )
    }

    static func grandTotalRow(value: String) -> NSMenuItem {
        boldRow(label: "Grand Total:", value: value)
    }

    static func noticeRow(_ text: String) -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: 28))
        let label = labelField(text, font: MenuFormat.captionFont, color: .secondaryLabelColor)
        label.frame = NSRect(x: inset, y: 4, width: MenuFormat.menuWidth - inset * 2, height: 20)
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)
        return customItem(view: container, height: 28)
    }

    static func errorRow(mode: String, message: String, diagnosticOutput: String? = nil) -> NSMenuItem {
        let fullMessage = Self.errorRowText(
            mode: mode,
            message: message,
            diagnosticOutput: diagnosticOutput
        )
        let verticalPadding: CGFloat = 4
        let copyGap: CGFloat = 8
        let textWidth = MenuFormat.menuWidth - inset * 2 - MenuFormat.copyButtonSize - copyGap
        let font = MenuFormat.captionFont
        let boundingRect = (fullMessage as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let hasDiagnosticOutput = diagnosticOutput?.isEmpty == false
        let maxHeight: CGFloat = hasDiagnosticOutput ? 240 : 120
        let textHeight = min(ceil(boundingRect.height), maxHeight)
        let totalHeight = textHeight + verticalPadding * 2
        let rowView = ErrorRowView(
            fullMessage: fullMessage,
            copyDescription: hasDiagnosticOutput ? "Copy error and command output" : "Copy error message",
            textWidth: textWidth,
            textHeight: textHeight,
            totalHeight: totalHeight,
            verticalPadding: verticalPadding
        )
        return customItem(view: rowView, height: totalHeight)
    }

    nonisolated static func errorRowText(mode: String, message: String, diagnosticOutput: String?) -> String {
        let error = "\(mode): \(message)"
        guard let diagnosticOutput, diagnosticOutput.isEmpty == false else { return error }
        return "\(error)\n\nclaude -p \"/usage\" output:\n\(diagnosticOutput)"
    }

    static func providerHeader(
        provider: ProviderID,
        report: ProviderReport,
        trailingSummary: String?
    ) -> NSMenuItem {
        let height: CGFloat = 28
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: height))
        let iconView = NSImageView(frame: NSRect(x: inset, y: 5, width: 18, height: 18))
        iconView.image = ProviderIcons.image(for: provider, report: report)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(iconView)

        let title = labelField(
            ReportLabels.heading(provider: provider, report: report),
            font: MenuFormat.subheadlineBoldFont,
            color: .labelColor
        )
        title.frame.origin = CGPoint(x: inset + 18 + 8, y: 6)
        title.sizeToFit()
        container.addSubview(title)

        if let trailingSummary {
            let summary = labelField(trailingSummary, font: MenuFormat.captionFont, color: .secondaryLabelColor)
            summary.sizeToFit()
            summary.frame.origin = CGPoint(x: MenuFormat.menuWidth - inset - summary.bounds.width, y: 7)
            container.addSubview(summary)
        }
        return customItem(view: container, height: height)
    }

    static func emptyState() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: 28))
        let label = labelField(
            "No enabled providers. Configure in Settings.",
            font: MenuFormat.captionFont,
            color: .secondaryLabelColor
        )
        label.frame.origin = CGPoint(x: inset, y: 6)
        label.sizeToFit()
        container.addSubview(label)
        return customItem(view: container, height: 28)
    }

    private static func twoColumnRow(
        label: String,
        value: String?,
        valueColor: NSColor,
        font: NSFont,
        height: CGFloat,
        caption: String? = nil,
        usedPercent: Double? = nil
    ) -> NSMenuItem {
        // Caption-less rows are kept compact (small symmetric padding) so the menu stays short when
        // many providers are enabled. A row WITH a caption renders it inside the same item with a
        // tight gap above, then adds `rowSpacing` below so the row+caption group reads as separate
        // from the next item.
        let topPad: CGFloat = 3
        let textHeight = height - 8
        let captionHeight: CGFloat = 13
        let intraGap: CGFloat = 2
        // The usage bar sits at the very bottom, below the caption, and only pushes the content up
        // when the padding that row already reserves is not deep enough to clear it. A barely-used
        // pool gets no bar and no band, so that row keeps its bar-less geometry.
        let barPercent = usedPercent.flatMap { UsageBarMetrics.showsBar(forPercent: $0) ? $0 : nil }
        let contentBottom = max(barPercent == nil ? 0 : Self.barBand, caption == nil ? topPad : rowSpacing)
        let captionField: NSTextField? = caption.map { text in
            let field = labelField(text, font: MenuFormat.captionFont, color: .secondaryLabelColor)
            field.lineBreakMode = .byTruncatingTail
            field.frame = NSRect(x: inset, y: contentBottom, width: MenuFormat.menuWidth - inset * 2, height: captionHeight)
            return field
        }
        let mainY: CGFloat = captionField == nil ? contentBottom : contentBottom + captionHeight + intraGap
        let totalHeight: CGFloat = mainY + textHeight + topPad
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: totalHeight))
        if let barPercent {
            container.addSubview(
                UsageBarView(
                    percent: barPercent,
                    frame: NSRect(
                        x: inset,
                        y: Self.barBottomPad,
                        width: MenuFormat.menuWidth - inset * 2,
                        height: Self.barHeight
                    )
                ))
        }
        if let captionField {
            container.addSubview(captionField)
        }
        let labelColor: NSColor = value == nil ? valueColor : .labelColor
        let left = labelField(label, font: font, color: labelColor)
        left.lineBreakMode = .byTruncatingTail
        guard let value else {
            left.frame = NSRect(x: inset, y: mainY, width: MenuFormat.menuWidth - inset * 2, height: height - 8)
            container.addSubview(left)
            return customItem(view: container, height: totalHeight)
        }
        // Give the value its natural width (so long values like Cursor credits aren't truncated)
        // and let the label take whatever remains, reserving a minimum for the label.
        let gap: CGFloat = 8
        let available = MenuFormat.menuWidth - inset * 2 - gap
        let right = labelField(value, font: font, color: valueColor)
        right.alignment = .right
        right.sizeToFit()
        left.sizeToFit()
        let minLabelWidth = min(left.frame.width, available * 0.45)
        let valueWidth = min(right.frame.width, available - minLabelWidth)
        let leftWidth = available - valueWidth
        left.frame = NSRect(x: inset, y: mainY, width: leftWidth, height: height - 8)
        right.frame = NSRect(x: MenuFormat.menuWidth - inset - valueWidth, y: mainY, width: valueWidth, height: height - 8)
        container.addSubview(left)
        container.addSubview(right)
        return customItem(view: container, height: totalHeight)
    }

    fileprivate static func labelField(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        return field
    }
}

/// The 2px usage indicator drawn under a limit row: a full-width track with the used share filled
/// in a color that escalates with the level. Drawn in `draw(_:)` rather than a layer background so
/// each `NSColor` resolves under the appearance in effect when the menu opens.
private final class UsageBarView: NSView {
    private let percent: Double

    /// Five bands with no semantic system-color equivalent, so each tone is supplied per appearance.
    private static func color(for level: UsageLevel) -> NSColor {
        switch level {
            case .low: Self.dynamic(light: (0.30, 0.76, 0.37), dark: (0.34, 0.82, 0.42))
            case .moderate: Self.dynamic(light: (0.12, 0.54, 0.22), dark: (0.18, 0.64, 0.29))
            case .high: Self.dynamic(light: (0.94, 0.63, 0.13), dark: (1.00, 0.69, 0.23))
            case .severe: Self.dynamic(light: (0.94, 0.42, 0.37), dark: (1.00, 0.49, 0.44))
            case .critical: Self.dynamic(light: (0.75, 0.15, 0.15), dark: (0.89, 0.23, 0.23))
        }
    }

    init(percent: Double, frame: NSRect) {
        self.percent = percent
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        self.bounds.fill()

        let fraction = UsageBarMetrics.fillFraction(forPercent: self.percent)
        guard fraction > 0 else { return }
        Self.color(for: UsageLevel.level(forPercent: self.percent)).setFill()
        NSRect(
            x: self.bounds.minX,
            y: self.bounds.minY,
            width: (self.bounds.width * fraction).rounded(),
            height: self.bounds.height
        ).fill()
    }

    private static func dynamic(
        light: (red: CGFloat, green: CGFloat, blue: CGFloat),
        dark: (red: CGFloat, green: CGFloat, blue: CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let components = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: components.red,
                green: components.green,
                blue: components.blue,
                alpha: 1
            )
        }
    }
}

private final class ErrorRowView: NSView {
    private let fullMessage: String
    private let copyDescription: String
    private let copyIcon: NSImageView
    private var copyIconFrame: NSRect = .zero
    private var copyRevertTask: Task<Void, Never>?

    init(
        fullMessage: String,
        copyDescription: String,
        textWidth: CGFloat,
        textHeight: CGFloat,
        totalHeight: CGFloat,
        verticalPadding: CGFloat
    ) {
        self.fullMessage = fullMessage
        self.copyDescription = copyDescription
        let label = UsageMenuItemViews.labelField(
            fullMessage,
            font: MenuFormat.captionFont,
            color: .systemRed
        )
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = textWidth
        label.frame = NSRect(
            x: UsageMenuItemViews.errorRowInset,
            y: verticalPadding,
            width: textWidth,
            height: textHeight
        )

        let icon = NSImageView(
            frame: NSRect(
                x: MenuFormat.menuWidth - UsageMenuItemViews.errorRowInset - MenuFormat.copyButtonSize,
                y: totalHeight - verticalPadding - MenuFormat.copyButtonSize,
                width: MenuFormat.copyButtonSize,
                height: MenuFormat.copyButtonSize
            )
        )
        icon.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: copyDescription
        )
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.toolTip = copyDescription
        self.copyIcon = icon
        self.copyIconFrame = icon.frame

        super.init(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: totalHeight))
        addSubview(label)
        addSubview(icon)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard self.copyIconFrame.contains(location) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(self.fullMessage, forType: .string)
        self.showCopyConfirmation()
    }

    private func showCopyConfirmation() {
        self.copyIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        self.copyRevertTask?.cancel()
        self.copyRevertTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard Task.isCancelled == false else { return }
            self?.copyIcon.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: self?.copyDescription
            )
        }
    }
}

extension UsageMenuItemViews {
    fileprivate static let errorRowInset: CGFloat = 12
}

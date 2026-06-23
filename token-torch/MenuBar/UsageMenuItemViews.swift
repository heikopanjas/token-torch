import AppKit

@MainActor
enum UsageMenuItemViews {
    private static let inset: CGFloat = 12
    /// Space added below a row that has an attached caption, so the row+caption group reads as
    /// separate from the next item. Caption-less rows stay compact.
    private static let rowSpacing: CGFloat = 7

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
        if isLoading {
            text = "Fetching data\u{2026}"
        }
        else if let result {
            text = "Updated \(result.fetchedAt.formatted(date: .omitted, time: .shortened))"
        }
        else {
            text = ""
        }
        if !text.isEmpty {
            let label = labelField(text, font: MenuFormat.captionFont, color: .secondaryLabelColor)
            label.frame.origin = CGPoint(x: inset, y: 6)
            label.sizeToFit()
            container.addSubview(label)
        }
        if isLoading {
            let spinner = NSProgressIndicator(frame: NSRect(x: MenuFormat.menuWidth - inset - 14, y: 7, width: 14, height: 14))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            container.addSubview(spinner)
        }
        return customItem(view: container, height: 28)
    }

    static func caption(_ text: String) -> NSMenuItem {
        twoColumnRow(label: text, value: nil, valueColor: .secondaryLabelColor, font: MenuFormat.captionFont, height: 22)
    }

    static func secondaryCaption(_ text: String) -> NSMenuItem {
        caption(text)
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

    static func costRow(label: String, value: String, caption: String? = nil) -> NSMenuItem {
        twoColumnRow(
            label: label,
            value: value,
            valueColor: .labelColor,
            font: MenuFormat.costRowBoldFont,
            height: 22,
            caption: caption
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

    static func errorRow(mode: String, message: String) -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: 36))
        let label = labelField("\(mode): \(message)", font: MenuFormat.captionFont, color: .systemRed)
        label.frame = NSRect(x: inset, y: 4, width: MenuFormat.menuWidth - inset * 2, height: 28)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        container.addSubview(label)
        return customItem(view: container, height: 36)
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
        caption: String? = nil
    ) -> NSMenuItem {
        // Caption-less rows are kept compact (small symmetric padding) so the menu stays short when
        // many providers are enabled. A row WITH a caption renders it inside the same item with a
        // tight gap above, then adds `rowSpacing` below so the row+caption group reads as separate
        // from the next item.
        let topPad: CGFloat = 3
        let textHeight = height - 8
        let captionHeight: CGFloat = 13
        let intraGap: CGFloat = 2
        let captionField: NSTextField? = caption.map { text in
            let field = labelField(text, font: MenuFormat.captionFont, color: .secondaryLabelColor)
            field.lineBreakMode = .byTruncatingTail
            field.frame = NSRect(x: inset, y: rowSpacing, width: MenuFormat.menuWidth - inset * 2, height: captionHeight)
            return field
        }
        let mainY: CGFloat = captionField == nil ? topPad : rowSpacing + captionHeight + intraGap
        let totalHeight: CGFloat = mainY + textHeight + topPad
        let container = NSView(frame: NSRect(x: 0, y: 0, width: MenuFormat.menuWidth, height: totalHeight))
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

    private static func labelField(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        return field
    }
}

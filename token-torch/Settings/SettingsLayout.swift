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
        return max(ceil(size.height) + 4, SettingsStyle.labelHeight)
    }

    static func makeSectionLabel(_ text: String, width: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: SettingsStyle.contentInset, y: y, width: width, height: SettingsStyle.labelHeight)
        label.autoresizingMask = [.minYMargin, .width]
        return label
    }

    static func makeCheckbox(
        title: String,
        width: CGFloat,
        y: CGFloat,
        target: AnyObject?,
        action: Selector?
    ) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: target, action: action)
        checkbox.frame = NSRect(x: SettingsStyle.contentInset, y: y, width: width, height: SettingsStyle.controlHeight)
        checkbox.autoresizingMask = [.minYMargin, .width]
        return checkbox
    }

    static func makeRoundedButton(
        title: String,
        width: CGFloat,
        x: CGFloat,
        y: CGFloat,
        target: AnyObject?,
        action: Selector?
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: x, y: y, width: width, height: SettingsStyle.controlHeight)
        button.autoresizingMask = [.minYMargin]
        return button
    }

    static func makeStatusLabel(width: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: SettingsStyle.contentInset, y: y, width: width, height: SettingsStyle.labelHeight)
        label.autoresizingMask = [.minYMargin, .width]
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    static func placeHint(
        _ text: String,
        width: CGFloat,
        x: CGFloat,
        y: CGFloat,
        gapBelow: CGFloat = 4
    ) -> (label: NSTextField, newY: CGFloat) {
        let hint = Self.makeHintLabel(text)
        let hintHeight = Self.measuredHintHeight(hint, width: width)
        hint.frame = NSRect(x: x, y: y - hintHeight, width: width, height: hintHeight)
        let newY = y - gapBelow - hintHeight
        return (hint, newY)
    }

    static func showError(_ message: String, on statusLabel: NSTextField) -> Void {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = Redaction.redactSecrets(message)
    }

    static func showStatus(_ message: String, on statusLabel: NSTextField) -> Void {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = message
    }

    static func persistKeychainField(
        value: String,
        provider: ProviderID,
        kind: AppKeyKind,
        using keychain: AppKeychainStore,
        statusLabel: NSTextField
    ) {
        do {
            if value.isEmpty == true {
                try keychain.delete(provider: provider, kind: kind)
            }
            else {
                try keychain.save(provider: provider, kind: kind, value: value)
            }
            Self.showStatus("Saved.", on: statusLabel)
        }
        catch {
            Self.showError(error.localizedDescription, on: statusLabel)
        }
    }

    static func clearKeychainField(
        provider: ProviderID,
        kind: AppKeyKind,
        using keychain: AppKeychainStore,
        statusLabel: NSTextField,
        successMessage: String
    ) {
        try? keychain.delete(provider: provider, kind: kind)
        Self.showStatus(successMessage, on: statusLabel)
    }

    struct SecureFieldSection {
        let titleLabel: NSTextField
        let hintLabel: NSTextField?
        let field: NSSecureTextField
        let saveButton: NSButton
        let clearButton: NSButton
        let newY: CGFloat
    }

    static func addSecureFieldSection(
        to view: NSView,
        title: String,
        hint: String?,
        placeholder: String,
        saveTitle: String,
        clearTitle: String,
        saveButtonWidth: CGFloat,
        clearButtonWidth: CGFloat,
        clearButtonSpacing: CGFloat = 8,
        width: CGFloat,
        x: CGFloat,
        y: CGFloat,
        target: AnyObject?,
        saveAction: Selector,
        clearAction: Selector
    ) -> SecureFieldSection {
        var currentY = y
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: x, y: currentY, width: width, height: SettingsStyle.labelHeight)
        titleLabel.autoresizingMask = [.minYMargin, .width]
        view.addSubview(titleLabel)

        var hintLabel: NSTextField? = nil
        if let hint {
            let placed = Self.placeHint(hint, width: width, x: x, y: currentY)
            hintLabel = placed.label
            view.addSubview(placed.label)
            currentY = placed.newY
        }

        currentY -= Self.groupedControlGap + SettingsStyle.controlHeight
        let field = NSSecureTextField(frame: NSRect(x: x, y: currentY, width: width, height: SettingsStyle.controlHeight))
        field.placeholderString = placeholder
        field.autoresizingMask = [.minYMargin, .width]
        view.addSubview(field)

        currentY -= SettingsStyle.labelHeight + SettingsStyle.controlHeight
        let saveButton = Self.makeRoundedButton(
            title: saveTitle,
            width: saveButtonWidth,
            x: x,
            y: currentY,
            target: target,
            action: saveAction
        )
        view.addSubview(saveButton)

        let clearButton = Self.makeRoundedButton(
            title: clearTitle,
            width: clearButtonWidth,
            x: x + saveButtonWidth + clearButtonSpacing,
            y: currentY,
            target: target,
            action: clearAction
        )
        view.addSubview(clearButton)

        return SecureFieldSection(
            titleLabel: titleLabel,
            hintLabel: hintLabel,
            field: field,
            saveButton: saveButton,
            clearButton: clearButton,
            newY: currentY
        )
    }

    static func addCheckboxWithHint(
        to view: NSView,
        title: String,
        hint: String,
        width: CGFloat,
        x: CGFloat,
        y: CGFloat,
        sectionGapAbove: CGFloat,
        target: AnyObject?,
        action: Selector
    ) -> (checkbox: NSButton, hintLabel: NSTextField, newY: CGFloat) {
        var currentY = y - sectionGapAbove - SettingsStyle.controlHeight
        let checkbox = Self.makeCheckbox(
            title: title,
            width: width,
            y: currentY,
            target: target,
            action: action
        )
        view.addSubview(checkbox)

        let placed = Self.placeHint(hint, width: width, x: x, y: currentY, gapBelow: Self.groupedControlGap)
        view.addSubview(placed.label)
        return (checkbox, placed.label, placed.newY)
    }
}

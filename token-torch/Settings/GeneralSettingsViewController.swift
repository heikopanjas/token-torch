import AppKit

@MainActor
final class GeneralSettingsViewController: SettingsPaneViewController {
    private static let intervalOptions: [(title: String, minutes: Int)] = [
        ("Every 5 minutes", 5),
        ("Every 10 minutes", 10),
        ("Every 15 minutes", 15),
        ("Every 30 minutes", 30),
        ("Every 60 minutes", 60),
        ("Every 3 hours", 180),
        ("Every 6 hours", 360),
        ("Every 12 hours", 720),
        ("Every day", 1440)
    ]

    private static let orderRowType = NSPasteboard.PasteboardType("private.tokentorch.providerOrderRow")
    private static let orderRowHeight: CGFloat = 26
    private static let orderHeaderHeight: CGFloat = 24

    private enum Column {
        static let view = NSUserInterfaceItemIdentifier("view")
        static let type = NSUserInterfaceItemIdentifier("type")
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
    }

    var onRefreshIntervalChanged: (() -> Void)?

    private var startAtLoginToggle: NSButton!
    private var intervalLabel: NSTextField!
    private var intervalPopup: NSPopUpButton!
    private var currencyLabel: NSTextField!
    private var currencyPopup: NSPopUpButton!
    private var vatLabel: NSTextField!
    private var vatField: NSTextField!
    private var deductVATToggle: NSButton!
    private var iconLabel: NSTextField!
    private var iconPopup: NSPopUpButton!
    private let currencies = DisplayCurrency.allCases
    private var orderLabel: NSTextField!
    private var orderTable: NSTableView!
    private var orderItems: [ProviderSection] = ProviderSection.allSections
    private var infoLabel: NSTextField!

    override var paneHeight: CGFloat { SettingsStyle.generalPaneHeight }

    override func makeContentView() -> NSView {
        let w = SettingsStyle.paneWidth
        let h = self.paneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - x - 16

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        y -= 6
        startAtLoginToggle = NSButton(
            checkboxWithTitle: "Start at login",
            target: self,
            action: #selector(startAtLoginChanged)
        )
        startAtLoginToggle.frame = NSRect(x: x, y: y, width: controlW, height: 22)
        startAtLoginToggle.autoresizingMask = [.minYMargin, .width]
        content.addSubview(startAtLoginToggle)

        y -= 16 + 16
        intervalLabel = NSTextField(labelWithString: "Refresh interval")
        intervalLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        intervalLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(intervalLabel)

        y -= 4 + 26
        intervalPopup = NSPopUpButton(frame: NSRect(x: x, y: y, width: controlW, height: 26), pullsDown: false)
        intervalPopup.autoresizingMask = [.minYMargin, .width]
        for option in Self.intervalOptions {
            intervalPopup.addItem(withTitle: option.title)
            intervalPopup.lastItem?.tag = option.minutes
        }
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)
        content.addSubview(intervalPopup)

        y -= 16 + 16
        currencyLabel = NSTextField(labelWithString: "Display currency")
        currencyLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        currencyLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(currencyLabel)

        y -= 4 + 26
        currencyPopup = NSPopUpButton(frame: NSRect(x: x, y: y, width: controlW, height: 26), pullsDown: false)
        currencyPopup.autoresizingMask = [.minYMargin, .width]
        for currency in currencies {
            currencyPopup.addItem(withTitle: "\(currency.rawValue) (\(currency.symbol))")
        }
        currencyPopup.target = self
        currencyPopup.action = #selector(currencyChanged)
        content.addSubview(currencyPopup)

        y -= 16 + 16
        vatLabel = NSTextField(labelWithString: "VAT rate (%)")
        vatLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        vatLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(vatLabel)

        y -= 4 + 26
        vatField = NSTextField(frame: NSRect(x: x, y: y, width: 120, height: 22))
        vatField.placeholderString = "0"
        vatField.autoresizingMask = [.minYMargin]
        vatField.target = self
        vatField.action = #selector(vatChanged)
        vatField.delegate = self
        content.addSubview(vatField)

        y -= 16 + 22
        deductVATToggle = NSButton(
            checkboxWithTitle: "Automatically deduct VAT",
            target: self,
            action: #selector(deductVATChanged)
        )
        deductVATToggle.frame = NSRect(x: x, y: y, width: controlW, height: 22)
        deductVATToggle.autoresizingMask = [.minYMargin, .width]
        content.addSubview(deductVATToggle)

        y -= 16 + 16
        iconLabel = NSTextField(labelWithString: "Menu bar icon")
        iconLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        iconLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(iconLabel)

        y -= 4 + 26
        iconPopup = NSPopUpButton(frame: NSRect(x: x, y: y, width: controlW, height: 26), pullsDown: false)
        iconPopup.autoresizingMask = [.minYMargin, .width]
        rebuildIconPopupItems()
        iconPopup.target = self
        iconPopup.action = #selector(iconChanged)
        content.addSubview(iconPopup)

        y -= 16 + 16
        orderLabel = NSTextField(labelWithString: "Providers")
        orderLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        orderLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(orderLabel)

        let tableHeight = Self.orderRowHeight * CGFloat(ProviderSection.allSections.count) + Self.orderHeaderHeight + 8
        y -= 4 + tableHeight
        let scroll = NSScrollView(frame: NSRect(x: x, y: y, width: controlW, height: tableHeight))
        scroll.autoresizingMask = [.minYMargin, .width]
        scroll.hasVerticalScroller = false
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false

        orderTable = NSTableView(frame: scroll.bounds)
        orderTable.headerView = NSTableHeaderView()
        orderTable.rowHeight = Self.orderRowHeight
        orderTable.gridStyleMask = []
        orderTable.usesAlternatingRowBackgroundColors = true
        orderTable.selectionHighlightStyle = .none
        orderTable.allowsMultipleSelection = false
        orderTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let viewColumn = NSTableColumn(identifier: Column.view)
        viewColumn.title = "Provider"
        viewColumn.width = 360
        viewColumn.minWidth = 200
        orderTable.addTableColumn(viewColumn)

        let typeColumn = NSTableColumn(identifier: Column.type)
        typeColumn.title = "Type"
        typeColumn.width = 150
        typeColumn.minWidth = 100
        orderTable.addTableColumn(typeColumn)

        let enabledColumn = NSTableColumn(identifier: Column.enabled)
        enabledColumn.title = "Enabled"
        enabledColumn.width = controlW - 360 - 150
        enabledColumn.minWidth = 70
        orderTable.addTableColumn(enabledColumn)

        orderTable.dataSource = self
        orderTable.delegate = self
        orderTable.registerForDraggedTypes([Self.orderRowType])
        orderTable.draggingDestinationFeedbackStyle = .gap
        scroll.documentView = orderTable
        content.addSubview(scroll)

        y -= 16
        infoLabel = SettingsLayout.makeHintLabel(GeneralSettingsCopy.providersTableHint)
        let infoHeight = SettingsLayout.measuredHintHeight(infoLabel, width: controlW)
        y -= infoHeight
        infoLabel.frame = NSRect(x: x, y: y, width: controlW, height: infoHeight)
        infoLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(infoLabel)

        return content
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let prefs = ProviderPreferencesStore.shared.load()
        let saved = prefs.refreshIntervalMinutes
        syncStartAtLoginToggle()
        if let index = (0 ..< intervalPopup.numberOfItems).first(where: { intervalPopup.item(at: $0)?.tag == saved }) {
            intervalPopup.selectItem(at: index)
        }
        else if let nearest = Self.intervalOptions.min(by: { abs($0.minutes - saved) < abs($1.minutes - saved) }) {
            // Migrate a value that is no longer offered (e.g. an old 20/25-minute setting).
            intervalPopup.selectItem(withTag: nearest.minutes)
            var updated = prefs
            updated.refreshIntervalMinutes = nearest.minutes
            ProviderPreferencesStore.shared.save(updated)
            onRefreshIntervalChanged?()
        }
        if let index = currencies.firstIndex(of: prefs.displayCurrency) {
            currencyPopup.selectItem(at: index)
        }
        vatField.stringValue = formatVATRate(prefs.vatRatePercent)
        deductVATToggle.state = prefs.automaticallyDeductVAT ? .on : .off
        rebuildIconPopupItems(selecting: prefs.menuBarIcon)
        orderItems = prefs.orderedSections()
        orderTable.reloadData()
    }

    @objc private func intervalChanged() {
        let minutes = intervalPopup.selectedItem?.tag ?? 15
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.refreshIntervalMinutes = minutes
        ProviderPreferencesStore.shared.save(prefs)
        onRefreshIntervalChanged?()
    }

    @objc private func startAtLoginChanged() {
        let enabled = startAtLoginToggle.state == .on
        do {
            try LoginItemRegistration.setEnabled(enabled)
            if enabled, LoginItemRegistration.requiresApproval {
                showLoginItemApprovalAlert()
            }
        }
        catch {
            syncStartAtLoginToggle()
            let alert = NSAlert()
            alert.messageText = "Could not update Start at login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func syncStartAtLoginToggle() {
        startAtLoginToggle.state = LoginItemRegistration.isEnabled ? .on : .off
    }

    private func showLoginItemApprovalAlert() {
        let alert = NSAlert()
        alert.messageText = "Approval required"
        alert.informativeText =
            "Open System Settings → General → Login Items and allow \(AppBrand.displayName) to open at login."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Login Items")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func currencyChanged() {
        let index = currencyPopup.indexOfSelectedItem
        guard currencies.indices.contains(index) else { return }
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.displayCurrency = currencies[index]
        ProviderPreferencesStore.shared.save(prefs)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    @objc private func vatChanged() {
        saveVATSettings()
    }

    @objc private func deductVATChanged() {
        saveVATSettings()
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.automaticallyDeductVAT = deductVATToggle.state == .on
        ProviderPreferencesStore.shared.save(prefs)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        saveVATSettings()
    }

    /// Persists the VAT rate from the text field. When the rate changes to a positive value,
    /// automatically enables deduction so entering a rate alone is enough to show net prices.
    private func saveVATSettings() {
        let parsed = Double(vatField.stringValue.replacingOccurrences(of: ",", with: ".")) ?? 0
        let normalized = DisplayPriceOptions.normalizeVATRate(parsed)
        var prefs = ProviderPreferencesStore.shared.load()
        let rateChanged = prefs.vatRatePercent != normalized
        guard rateChanged == true else { return }
        prefs.vatRatePercent = normalized
        if normalized > 0 {
            prefs.automaticallyDeductVAT = true
            deductVATToggle.state = .on
        }
        else {
            prefs.automaticallyDeductVAT = false
            deductVATToggle.state = .off
        }
        ProviderPreferencesStore.shared.save(prefs)
        vatField.stringValue = formatVATRate(prefs.vatRatePercent)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    private func formatVATRate(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func rebuildIconPopupItems(selecting selected: MenuBarIconProvider? = nil) {
        let prefs = ProviderPreferencesStore.shared.load()
        let current = selected ?? prefs.menuBarIcon
        iconPopup.removeAllItems()
        for provider in MenuBarIconProvider.allCases {
            iconPopup.addItem(withTitle: provider.displayName)
            iconPopup.lastItem?.image = MenuBarStatusIcon.previewImage(for: provider, preferences: prefs)
        }
        if let index = MenuBarIconProvider.allCases.firstIndex(of: current) {
            iconPopup.selectItem(at: index)
        }
    }

    @objc private func iconChanged() {
        let index = iconPopup.indexOfSelectedItem
        guard MenuBarIconProvider.allCases.indices.contains(index) else { return }
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.menuBarIcon = MenuBarIconProvider.allCases[index]
        ProviderPreferencesStore.shared.save(prefs)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    private func saveOrder() {
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.setSectionOrder(orderItems)
        ProviderPreferencesStore.shared.save(prefs)
        if prefs.menuBarIcon == .topOfProviderList {
            rebuildIconPopupItems(selecting: .topOfProviderList)
        }
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }

    @objc private func enabledToggled(_ sender: NSButton) {
        let row = orderTable.row(for: sender)
        guard orderItems.indices.contains(row) else { return }
        let enabled = sender.state == .on
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.setSection(orderItems[row], enabled: enabled)
        ProviderPreferencesStore.shared.save(prefs)
        if prefs.menuBarIcon == .topOfProviderList {
            rebuildIconPopupItems(selecting: .topOfProviderList)
        }
        if enabled == true {
            // Enabling needs fresh data (the last fetch omitted this view), so refetch.
            NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
            NotificationCenter.default.post(name: AppActions.tokenTorchRefreshRequested, object: nil)
        }
        else {
            // Disabling just drops the view from the menu; no network call needed.
            NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
        }
    }
}

extension GeneralSettingsViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === vatField else { return }
        saveVATSettings()
    }
}

extension GeneralSettingsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        orderItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard orderItems.indices.contains(row) else { return nil }
        let section = orderItems[row]
        switch tableColumn?.identifier {
            case Column.view: return makeViewCell(section)
            case Column.type: return makeTypeCell(section)
            case Column.enabled: return makeEnabledCell(section)
            default: return nil
        }
    }

    private func makeViewCell(_ section: ProviderSection) -> NSView {
        let cell = NSTableCellView()
        let imageView = NSImageView()
        imageView.image = ProviderIcons.generalSettingsImage(for: section, side: 16)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.imageView = imageView
        let textField = NSTextField(labelWithString: section.heading)
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func makeTypeCell(_ section: ProviderSection) -> NSView {
        let cell = NSTableCellView()
        let textField = NSTextField(labelWithString: ReportLabels.typeLabel(section.kind))
        textField.textColor = .secondaryLabelColor
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func makeEnabledCell(_ section: ProviderSection) -> NSView {
        let cell = NSTableCellView()
        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(enabledToggled(_:)))
        button.state = ProviderPreferencesStore.shared.load().isSectionEnabled(section) ? .on : .off
        button.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.orderRowType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard dropOperation == .above else {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard
            let item = info.draggingPasteboard.pasteboardItems?.first,
            let string = item.string(forType: Self.orderRowType),
            let sourceRow = Int(string),
            orderItems.indices.contains(sourceRow)
        else {
            return false
        }
        let moved = orderItems.remove(at: sourceRow)
        let target = sourceRow < row ? row - 1 : row
        orderItems.insert(moved, at: min(max(target, 0), orderItems.count))
        tableView.reloadData()
        saveOrder()
        return true
    }
}

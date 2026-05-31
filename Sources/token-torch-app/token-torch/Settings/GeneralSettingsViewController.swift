import AppKit
import TokenTorchCore

@MainActor
final class GeneralSettingsViewController: NSViewController {
    var onRefreshIntervalChanged: (() -> Void)?

    private var intervalLabel: NSTextField!
    private var intervalPopup: NSPopUpButton!
    private var currencyLabel: NSTextField!
    private var currencyPopup: NSPopUpButton!
    private let currencies = DisplayCurrency.allCases
    private var infoLabel: NSTextField!

    override var preferredContentSize: NSSize {
        get { isViewLoaded ? view.bounds.size : NSSize(width: SettingsStyle.paneWidth, height: SettingsStyle.generalPaneHeight) }
        set {}
    }

    override func loadView() {
        let w = SettingsStyle.paneWidth
        let h = SettingsStyle.generalPaneHeight
        let x = SettingsStyle.contentPadding
        let controlW = w - 2 * x
        var y = h - x - 16

        view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        intervalLabel = NSTextField(labelWithString: "Refresh interval")
        intervalLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        intervalLabel.autoresizingMask = [.minYMargin, .width]
        view.addSubview(intervalLabel)

        y -= 4 + 26
        intervalPopup = NSPopUpButton(frame: NSRect(x: x, y: y, width: controlW, height: 26), pullsDown: false)
        intervalPopup.autoresizingMask = [.minYMargin, .width]
        for minutes in stride(from: 5, through: 120, by: 5) {
            intervalPopup.addItem(withTitle: "Every \(minutes) minutes")
            intervalPopup.lastItem?.tag = minutes
        }
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)
        view.addSubview(intervalPopup)

        y -= 16 + 16
        currencyLabel = NSTextField(labelWithString: "Display currency")
        currencyLabel.frame = NSRect(x: x, y: y, width: controlW, height: 16)
        currencyLabel.autoresizingMask = [.minYMargin, .width]
        view.addSubview(currencyLabel)

        y -= 4 + 26
        currencyPopup = NSPopUpButton(frame: NSRect(x: x, y: y, width: controlW, height: 26), pullsDown: false)
        currencyPopup.autoresizingMask = [.minYMargin, .width]
        for currency in currencies {
            currencyPopup.addItem(withTitle: "\(currency.rawValue) (\(currency.symbol))")
        }
        currencyPopup.target = self
        currencyPopup.action = #selector(currencyChanged)
        view.addSubview(currencyPopup)

        y -= 16 + 60
        infoLabel = NSTextField(
            wrappingLabelWithString:
                "Subscription quotas import vendor OAuth into \(AppBrand.displayName)'s Keychain once (a login prompt is OK the first time). Routine refresh reads only \(AppBrand.displayName)'s copy. Admin keys below are stored in \(AppBrand.displayName)'s Keychain."
        )
        infoLabel.frame = NSRect(x: x, y: y, width: controlW, height: 60)
        infoLabel.autoresizingMask = [.minYMargin, .width]
        infoLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        infoLabel.textColor = .secondaryLabelColor
        view.addSubview(infoLabel)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let prefs = ProviderPreferencesStore.shared.load()
        if let index = (0 ..< intervalPopup.numberOfItems).first(where: { intervalPopup.item(at: $0)?.tag == prefs.refreshIntervalMinutes }) {
            intervalPopup.selectItem(at: index)
        }
        if let index = currencies.firstIndex(of: prefs.displayCurrency) {
            currencyPopup.selectItem(at: index)
        }
    }

    @objc private func intervalChanged() {
        let minutes = intervalPopup.selectedItem?.tag ?? 15
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.refreshIntervalMinutes = minutes
        ProviderPreferencesStore.shared.save(prefs)
        onRefreshIntervalChanged?()
    }

    @objc private func currencyChanged() {
        let index = currencyPopup.indexOfSelectedItem
        guard currencies.indices.contains(index) else { return }
        var prefs = ProviderPreferencesStore.shared.load()
        prefs.displayCurrency = currencies[index]
        ProviderPreferencesStore.shared.save(prefs)
        NotificationCenter.default.post(name: AppActions.tokenTorchDisplayChanged, object: nil)
    }
}

import AppKit
import TokenTorchCore

enum MenuBarStatusIcon {
    private static let side: CGFloat = 18

    static func image() -> NSImage? {
        let prefs = ProviderPreferencesStore.shared.load()
        return image(for: prefs.menuBarIcon, preferences: prefs)
    }

    static func image(for provider: MenuBarIconProvider, preferences: ProviderPreferences? = nil) -> NSImage? {
        let prefs = preferences ?? ProviderPreferencesStore.shared.load()
        guard let resourceName = pdfResourceName(for: provider, preferences: prefs) else {
            return fallbackSymbol
        }
        if let pdf = pdfImage(named: resourceName) {
            return pdf
        }
        return fallbackSymbol
    }

    static func previewImage(
        for provider: MenuBarIconProvider,
        preferences: ProviderPreferences? = nil,
        side: CGFloat = 16
    ) -> NSImage? {
        let prefs = preferences ?? ProviderPreferencesStore.shared.load()
        guard let resourceName = pdfResourceName(for: provider, preferences: prefs) else {
            return fallbackSymbol.map {
                let copy = $0.copy() as? NSImage ?? $0
                copy.size = NSSize(width: side, height: side)
                return copy
            }
        }
        return pdfImage(named: resourceName, side: side)
            ?? fallbackSymbol.map {
                let copy = $0.copy() as? NSImage ?? $0
                copy.size = NSSize(width: side, height: side)
                return copy
            }
    }

    private static func pdfResourceName(for provider: MenuBarIconProvider, preferences: ProviderPreferences) -> String? {
        if provider == .topOfProviderList {
            guard let section = preferences.topProviderSection else { return nil }
            return ProviderIcons.generalSettingsResourceName(for: section.provider, kind: section.kind)
        }
        return provider.pdfResourceName
    }

    private static var fallbackSymbol: NSImage? {
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

    private static func pdfImage(named name: String, side: CGFloat = side) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        return image
    }
}

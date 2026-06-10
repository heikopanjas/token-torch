import AppKit
import TokenTorchCore

enum MenuBarStatusIcon {
    private static let side: CGFloat = 18

    static func image() -> NSImage? {
        image(for: ProviderPreferencesStore.shared.load().menuBarIcon)
    }

    static func image(for provider: MenuBarIconProvider) -> NSImage? {
        if let pdf = pdfImage(named: provider.pdfResourceName) {
            return pdf
        }
        return fallbackSymbol
    }

    static func previewImage(for provider: MenuBarIconProvider, side: CGFloat = 16) -> NSImage? {
        pdfImage(named: provider.pdfResourceName, side: side) ?? fallbackSymbol.map {
            let copy = $0.copy() as? NSImage ?? $0
            copy.size = NSSize(width: side, height: side)
            return copy
        }
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

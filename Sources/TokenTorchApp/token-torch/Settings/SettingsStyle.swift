import AppKit

enum SettingsStyle {
    static let paneWidth: CGFloat = 840
    static let toolbarIconPointSize: CGFloat = 16
    /// A `.preference`-style toolbar upscales non-symbol (PDF/bitmap) item
    /// images to fill its icon slot (~35pt), but leaves SF Symbols at their
    /// configured point size — so provider PDFs render much larger than the
    /// neighboring `gearshape`/`wrench.and.screwdriver` symbols. To match, each
    /// provider logo is composited into a transparent square canvas wider than
    /// the slot (so the toolbar stops upscaling) with the logo drawn at
    /// `toolbarProviderLogoBox`, fitted to the displayed SF Symbol box.
    static let toolbarProviderCanvasSide: CGFloat = 40
    static let toolbarProviderLogoBox: CGFloat = 23
    static let contentPadding: CGFloat = 20
    static let generalPaneHeight: CGFloat = 500
    static let providerPaneHeight: CGFloat = 380
    static let providerQuotaOnlyPaneHeight: CGFloat = 240
    static let advancedPaneHeight: CGFloat = 360
}

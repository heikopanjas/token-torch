import AppKit

@MainActor
class SettingsPaneViewController: NSViewController {
    var paneHeight: CGFloat { SettingsStyle.generalPaneHeight }

    override var preferredContentSize: NSSize {
        get {
            if self.isViewLoaded == true {
                return self.view.bounds.size
            }
            return NSSize(width: SettingsStyle.paneWidth, height: self.paneHeight)
        }
        set {}
    }
}

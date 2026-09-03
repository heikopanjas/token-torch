import AppKit

@MainActor
class SettingsPaneViewController: NSViewController {
    var paneHeight: CGFloat { SettingsStyle.generalPaneHeight }

    /// Subclasses build their pane here — at full `paneHeight`, top-down, as before — instead of
    /// overriding `loadView()`. The base class hosts the result as the document of a scroll view so
    /// a pane taller than the settings window scrolls. The settings window size is deliberate:
    /// never grow a pane's window to fit its content, make the content scroll.
    func makeContentView() -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: SettingsStyle.paneWidth, height: self.paneHeight))
    }

    override func loadView() {
        let content = self.makeContentView()
        let scrollView = NSScrollView(frame: content.frame)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        content.autoresizingMask = [.width]
        scrollView.documentView = content
        self.view = scrollView
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        self.scrollToTop()
    }

    /// Panes shorter than the window still stretch to fill it, exactly as they did when the pane was
    /// the window's content view; only a pane taller than the window scrolls.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard let scrollView = self.view as? NSScrollView, let content = scrollView.documentView else { return }
        let height = max(self.paneHeight, scrollView.contentView.bounds.height)
        if content.frame.height != height {
            content.setFrameSize(NSSize(width: content.frame.width, height: height))
        }
    }

    /// A non-flipped document view rests at its bottom-left, but panes lay out downward from the
    /// top, so a clipped pane would otherwise open showing its last row.
    private func scrollToTop() {
        guard let scrollView = self.view as? NSScrollView, let content = scrollView.documentView else { return }
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(content.bounds.height - clip.bounds.height, 0)))
        scrollView.reflectScrolledClipView(clip)
    }

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

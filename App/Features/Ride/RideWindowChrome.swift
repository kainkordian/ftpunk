#if os(macOS)
import AppKit
import SwiftUI

/// Extends only the dashboard into the title-bar region. Leaving it restores the shell's chrome.
struct RideWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.apply() }
    static func dismantleNSView(_ view: ChromeView, coordinator: ()) { view.restore() }

    final class ChromeView: NSView {
        private weak var appliedWindow: NSWindow?
        private var originalTitleVisibility: NSWindow.TitleVisibility = .visible
        private var originalTransparent = false
        private var originalFullSize = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() {
            guard let window, appliedWindow !== window else { return }
            restore()
            appliedWindow = window
            originalTitleVisibility = window.titleVisibility
            originalTransparent = window.titlebarAppearsTransparent
            originalFullSize = window.styleMask.contains(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
        func restore() {
            guard let window = appliedWindow else { return }
            window.titleVisibility = originalTitleVisibility
            window.titlebarAppearsTransparent = originalTransparent
            if !originalFullSize { window.styleMask.remove(.fullSizeContentView) }
            appliedWindow = nil
        }
    }
}
#endif

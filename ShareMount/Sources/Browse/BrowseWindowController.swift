import Cocoa
import SwiftUI

/// The "Browse Network" window. Bonjour browsing runs only while it's open.
final class BrowseWindowController: NSObject, NSWindowDelegate {

    private let browser = NetworkBrowser()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: BrowseView(browser: browser))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Browse Network"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 640, height: 420))
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            window = win
        }
        browser.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        browser.stop()
    }
}

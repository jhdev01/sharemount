import Cocoa
import SwiftUI

/// The Add a Drive window. Starts fresh each time it opens; Bonjour browsing
/// runs only while it's open.
final class AddDriveWindowController: NSObject, NSWindowDelegate {

    private let browser = NetworkBrowser()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let view = AddDriveView(browser: browser) { [weak self] in
                // Close after the button's action has finished.
                DispatchQueue.main.async { self?.window?.close() }
            }
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Add a Drive"
            win.styleMask = [.titled, .closable, .resizable]
            win.setContentSize(NSSize(width: 720, height: 500))
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
        window = nil   // next open starts with a clean slate
    }
}

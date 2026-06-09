import Cocoa
import SwiftUI

/// Lazily creates and re-shows a single Preferences window hosting the SwiftUI
/// view. Kept alive (`isReleasedWhenClosed = false`) so reopening is instant.
final class PreferencesWindowController {

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PreferencesView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "ShareMount Preferences"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.setContentSize(NSSize(width: 520, height: 360))
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        // An accessory app isn't frontmost by default; activate so the window
        // takes focus.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

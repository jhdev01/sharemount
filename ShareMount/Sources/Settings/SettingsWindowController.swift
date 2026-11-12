import Cocoa
import SwiftUI

/// The single Settings window; reopening it is instant.
final class SettingsWindowController {

    private let router = SettingsRouter()
    private var window: NSWindow?
    private let addDrive: () -> Void

    init(addDrive: @escaping () -> Void) {
        self.addDrive = addDrive
    }

    /// Show Settings, optionally jumping to one drive.
    func show(selecting id: Share.ID? = nil) {
        if let id {
            router.page = .drive(id)
        } else if router.page == nil {
            router.page = ShareStore.shared.shares.first.map { .drive($0.id) } ?? .general
        }
        if window == nil {
            let view = SettingsView(router: router, store: .shared, manager: .shared, addDrive: addDrive)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "ShareMount Settings"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.setContentSize(NSSize(width: 820, height: 560))
            win.isReleasedWhenClosed = false
            win.center()
            win.setFrameAutosaveName("SettingsWindow")
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

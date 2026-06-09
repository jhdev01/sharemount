import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory` = menu-bar-only agent: no Dock icon, no app-switcher
        // entry. This pairs with `LSUIElement` in Info.plist.
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusItemController()
    }
}

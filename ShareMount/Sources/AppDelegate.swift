import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusController: StatusItemController?
    private let addDriveWindow = AddDriveWindowController()
    private lazy var settingsWindow = SettingsWindowController { [weak self] in
        self?.showAddDrive()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory` = menu-bar-only agent: no Dock icon, no app-switcher
        // entry. This pairs with `LSUIElement` in Info.plist.
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        LoginItem.syncAtLaunch()
        ConnectionManager.shared.start()
        statusController = StatusItemController(
            addDrive: { [weak self] in self?.showAddDrive() },
            openSettings: { [weak self] id in self?.openSettings(selecting: id) })

        // First run: nothing configured yet, so go straight to adding a drive.
        if ShareStore.shared.shares.isEmpty {
            showAddDrive()
        }
    }

    @objc func showAddDrive() {
        addDriveWindow.show()
    }

    @objc func showSettings() {
        openSettings(selecting: nil)
    }

    private func openSettings(selecting id: Share.ID?) {
        settingsWindow.show(selecting: id)
    }

    /// An accessory app never shows its main menu, but AppKit still routes key
    /// equivalents through it. Without an Edit menu, ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z
    /// do nothing in the Preferences text fields, and ⌘W doesn't close windows.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Add a Drive…", action: #selector(showAddDrive), keyEquivalent: "n")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ShareMount",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}

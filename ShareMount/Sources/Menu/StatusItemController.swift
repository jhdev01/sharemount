import Cocoa

/// Owns the menu bar item and its menu. The menu is rebuilt every time it
/// opens so connection state is always current.
final class StatusItemController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private lazy var preferences = PreferencesWindowController()
    private lazy var browseWindow = BrowseWindowController()
    private let workQueue = DispatchQueue(label: "ShareMount.mount", qos: .userInitiated)

    override init() {
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below",
                                   accessibilityDescription: "Network drives")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: Menu building

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        let shares = ShareStore.shared.shares

        if shares.isEmpty {
            let empty = NSMenuItem(title: "No shares configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for share in shares {
                let item = NSMenuItem(title: share.displayName,
                                      action: #selector(toggleShare(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = share
                let mounted = MountManager.isMounted(share)
                item.state = mounted ? .on : .off
                if !mounted, let problem = AutoConnector.shared.lastErrors[share.id] {
                    item.image = NSImage(systemSymbolName: "exclamationmark.triangle",
                                         accessibilityDescription: "Problem")
                    item.toolTip = problem
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let browse = NSMenuItem(title: "Browse Network…",
                                action: #selector(openBrowser),
                                keyEquivalent: "b")
        browse.target = self
        menu.addItem(browse)

        let prefs = NSMenuItem(title: "Preferences…",
                               action: #selector(openPreferences),
                               keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let quit = NSMenuItem(title: "Quit ShareMount",
                              action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func toggleShare(_ sender: NSMenuItem) {
        guard let share = sender.representedObject as? Share else { return }
        if MountManager.isMounted(share) {
            AutoConnector.shared.userDidDisconnect(share)
            disconnect(share)
        } else {
            AutoConnector.shared.userDidConnect(share)
            connect(share, credentials: KeychainStore.load(server: share.host ?? ""))
        }
    }

    /// Mount in the background. If credentials are missing or rejected, prompt
    /// and retry. On success, remember the credentials for next time.
    private func connect(_ share: Share, credentials: Credentials?) {
        let server = share.host ?? ""
        workQueue.async {
            do {
                try MountManager.mount(share, credentials: credentials)
                if let credentials { KeychainStore.save(credentials, server: server) }
            } catch MountError.authRequired {
                DispatchQueue.main.async { self.promptAndRetry(share) }
            } catch MountError.invalidURL {
                DispatchQueue.main.async {
                    self.notifyFailure(share, message: "“\(share.location)” isn’t a valid SMB location.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.notifyFailure(share, message: "Could not connect.\n\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func promptAndRetry(_ share: Share) {
        let server = share.host ?? ""
        let prefill = KeychainStore.load(server: server)?.username ?? ""
        guard let creds = CredentialPrompt.ask(for: share, prefillUser: prefill) else { return }
        workQueue.async {
            do {
                try MountManager.mount(share, credentials: creds)
                KeychainStore.save(creds, server: server)
            } catch MountError.authRequired {
                DispatchQueue.main.async {
                    self.notifyFailure(share, message: "The username or password was incorrect.")
                }
            } catch {
                DispatchQueue.main.async {
                    self.notifyFailure(share, message: "Could not connect.\n\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func disconnect(_ share: Share) {
        workQueue.async {
            do {
                try MountManager.unmount(share)
            } catch {
                DispatchQueue.main.async {
                    self.notifyFailure(share, message: "Could not disconnect.\n\n\(error.localizedDescription)")
                }
            }
        }
    }

    private func notifyFailure(_ share: Share, message: String) {
        let alert = NSAlert()
        alert.messageText = share.displayName
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openBrowser() {
        browseWindow.show()
    }

    @objc private func openPreferences() {
        preferences.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

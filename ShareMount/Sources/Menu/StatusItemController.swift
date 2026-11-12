import Cocoa
import Combine
import SwiftUI

/// Owns the menu bar icon and the panel (popover) it opens.
final class StatusItemController: NSObject {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var stateObserver: AnyCancellable?

    init(addDrive: @escaping () -> Void, openSettings: @escaping (Share.ID?) -> Void) {
        super.init()

        let actions = PanelActions(
            addDrive: { [weak self] in self?.closePanel(); addDrive() },
            openSettings: { [weak self] id in self?.closePanel(); openSettings(id) },
            quit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: MenuPanelView(
            manager: .shared, store: .shared, actions: actions))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient

        if let button = statusItem.button {
            button.action = #selector(togglePanel(_:))
            button.target = self
        }
        updateIcon()
        stateObserver = ConnectionManager.shared.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        ConnectionManager.shared.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePanel() {
        popover.performClose(nil)
    }

    /// Plain drive icon; a warning badge when a drive needs attention.
    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let needsAttention = ConnectionManager.shared.states.values.contains { $0.needsAttention }
        let name = needsAttention ? "externaldrive.badge.exclamationmark"
                                  : "externaldrive.connected.to.line.below"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "ShareMount")
            ?? NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "ShareMount")
        image?.isTemplate = true
        button.image = image
        button.toolTip = needsAttention ? "ShareMount — a drive needs attention" : "ShareMount"
    }
}

import SwiftUI

/// What the panel's buttons do; supplied by `StatusItemController`, which
/// closes the popover first.
struct PanelActions {
    var addDrive: () -> Void
    var openSettings: (Share.ID?) -> Void
    var quit: () -> Void
}

/// The popover shown from the menu bar icon.
struct MenuPanelView: View {

    @ObservedObject var manager: ConnectionManager
    @ObservedObject var store: ShareStore
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 14)
            if store.shares.isEmpty {
                emptyState
            } else if store.shares.count > 6 {
                ScrollView { driveList }.frame(height: 380)
            } else {
                driveList
            }
            Divider()
            menuButtons
            footer
        }
        .frame(width: 340)
    }

    // MARK: Header

    private var connectedCount: Int {
        store.shares.filter { manager.state(of: $0).isConnected }.count
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ShareMount").font(.system(size: 15, weight: .bold))
                Text(store.shares.isEmpty
                     ? "No drives yet"
                     : "\(connectedCount) of \(store.shares.count) drives connected")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !store.shares.isEmpty {
                Button("Connect All") { manager.connectAll() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(connectedCount == store.shares.count)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: Drives

    private struct DriveGroup: Identifiable {
        let name: String
        var shares: [Share]
        var id: String { name }
    }

    /// Drives grouped by computer, in the order they were added.
    private var groups: [DriveGroup] {
        var result: [DriveGroup] = []
        for share in store.shares {
            let name = share.computerName
            if let index = result.firstIndex(where: { $0.name == name }) {
                result[index].shares.append(share)
            } else {
                result.append(DriveGroup(name: name, shares: [share]))
            }
        }
        return result
    }

    private var driveList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                Text(group.name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(group.shares) { share in
                    DriveRow(share: share, state: manager.state(of: share),
                             manager: manager, actions: actions)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("Add a drive from another computer and ShareMount will keep it connected.")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a Drive…", action: actions.addDrive)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    // MARK: Menu + footer

    private var menuButtons: some View {
        VStack(spacing: 0) {
            Button(action: actions.addDrive) {
                MenuRowLabel(title: "Add a Drive…", systemImage: "plus", shortcut: "⌘N")
            }
            .keyboardShortcut("n")
            Button { actions.openSettings(nil) } label: {
                MenuRowLabel(title: "Settings…", systemImage: "gearshape", shortcut: "⌘,")
            }
            .keyboardShortcut(",")
            Button(action: actions.quit) {
                MenuRowLabel(title: "Quit ShareMount", systemImage: "power", shortcut: "⌘Q")
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(MenuRowButtonStyle())
        .padding(6)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if LoginItem.isEnabled {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(nsColor: .systemGreen))
                Text("Opens at login · keeps drives connected")
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(Color(nsColor: .systemOrange))
                Text("Won’t open at login")
                Spacer()
                Button("Fix…") { actions.openSettings(nil) }
                    .buttonStyle(.link)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
}

// MARK: - One drive

private struct DriveRow: View {
    let share: Share
    let state: DriveState
    let manager: ConnectionManager
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 10) {
            StatusIcon(state: state, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(share.displayName.isEmpty ? "Untitled" : share.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(state.summary(for: share))
                    .font(.system(size: 11.5))
                    .foregroundColor(state == .off ? .secondary : Color(nsColor: state.tint))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Settings for “\(share.displayName)”…") { actions.openSettings(share.id) }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .connected:
            HStack(spacing: 0) {
                IconButton(systemImage: "folder", label: "Open \(share.displayName) in Finder") {
                    manager.openInFinder(share)
                }
                IconButton(systemImage: "eject", label: "Disconnect \(share.displayName)") {
                    manager.disconnect(share)
                }
            }
        case .connecting:
            ProgressView().controlSize(.small).padding(.trailing, 8)
        case .needsPassword:
            Button("Sign In…") { manager.signIn(share) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .problem:
            Button("Retry") { manager.connect(share) }
                .controlSize(.small)
        case .off:
            Button("Connect") { manager.connect(share) }
                .controlSize(.small)
        case .invalid:
            Button("Fix…") { actions.openSettings(share.id) }
                .controlSize(.small)
        }
    }
}

/// Rounded, tinted square with the drive's status symbol.
struct StatusIcon: View {
    let state: DriveState
    var size: CGFloat = 32

    var body: some View {
        let tint = Color(nsColor: state.tint)
        RoundedRectangle(cornerRadius: size / 4)
            .fill(tint.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: state.symbolName)
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundColor(tint)
            )
            .accessibilityHidden(true)
    }
}

private struct IconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Menu-style rows

private struct MenuRowLabel: View {
    let title: String
    let systemImage: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).frame(width: 16)
            Text(title)
            Spacer()
            Text(shortcut).opacity(0.6)
        }
        .font(.system(size: 13))
    }
}

/// Highlights on hover like a real menu item.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .frame(height: 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(hovering ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering || configuration.isPressed ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

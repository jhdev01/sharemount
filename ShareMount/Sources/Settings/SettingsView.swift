import SwiftUI

enum SettingsPage: Hashable {
    case drive(Share.ID)
    case general
}

/// Lets the window controller choose which page Settings shows.
final class SettingsRouter: ObservableObject {
    @Published var page: SettingsPage?
}

struct SettingsView: View {

    @ObservedObject var router: SettingsRouter
    @ObservedObject var store: ShareStore
    @ObservedObject var manager: ConnectionManager
    let addDrive: () -> Void

    var body: some View {
        NavigationSplitView {
            List(selection: $router.page) {
                Section("Drives") {
                    ForEach(store.shares) { share in
                        SidebarDriveRow(share: share, state: manager.state(of: share))
                            .tag(SettingsPage.drive(share.id))
                    }
                    Button(action: addDrive) {
                        Label("Add a Drive…", systemImage: "plus")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)
                }
                Section("App") {
                    Label("General", systemImage: "gearshape")
                        .tag(SettingsPage.general)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.page {
        case .drive(let id):
            if let share = store.shares.first(where: { $0.id == id }) {
                DriveDetailView(share: share, manager: manager)
                    .id(id)
            } else {
                placeholder
            }
        case .general:
            GeneralSettingsView()
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text(store.shares.isEmpty ? "No drives yet." : "Choose a drive on the left.")
                .foregroundColor(.secondary)
            if store.shares.isEmpty {
                Button("Add a Drive…", action: addDrive)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SidebarDriveRow: View {
    let share: Share
    let state: DriveState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(nsColor: state.tint))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(share.displayName.isEmpty ? "Untitled" : share.displayName)
                    .lineLimit(1)
                Text(share.computerName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

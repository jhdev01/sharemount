import SwiftUI

struct PreferencesView: View {

    // Edit a working copy; commit to the store on every change.
    @State private var shares: [Share] = ShareStore.shared.shares
    @State private var selection: Share.ID?
    @State private var launchAtLogin: Bool = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                shareList.frame(minWidth: 180)
                detail.frame(minWidth: 280)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 360)
        // Pick up shares added elsewhere (e.g. Browse Network → Add to Menu).
        .onReceive(ShareStore.shared.$shares) { latest in
            if latest != shares { shares = latest }
        }
    }

    // MARK: List

    private var shareList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(shares) { share in
                    Text(share.displayName.isEmpty ? "Untitled" : share.displayName)
                        .tag(share.id)
                }
            }
            HStack(spacing: 2) {
                Button(action: addShare) { Image(systemName: "plus") }
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            Form {
                TextField("Display name", text: Binding(
                    get: { shares[index].displayName },
                    set: { shares[index].displayName = $0; persist() }))

                TextField("Network location", text: Binding(
                    get: { shares[index].location },
                    set: { shares[index].location = $0; persist() }))

                Text("Example: smb://192.168.1.10/Media")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        } else {
            Text("Select a share, or click + to add one.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    LoginItem.setEnabled(newValue)
                    let actual = LoginItem.isEnabled
                    if actual != newValue { launchAtLogin = actual }   // revert on failure
                }
            Spacer()
        }
        .padding()
    }

    // MARK: Mutations

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return shares.firstIndex { $0.id == selection }
    }

    private func addShare() {
        let new = Share(displayName: "New Share", location: "")
        shares.append(new)
        selection = new.id
        persist()
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        shares.remove(at: index)
        selection = nil
        persist()
    }

    private func persist() {
        ShareStore.shared.replaceAll(shares)
    }
}

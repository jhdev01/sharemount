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
        .frame(minWidth: 600, minHeight: 460)
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

                Toggle("Connect automatically", isOn: Binding(
                    get: { shares[index].autoConnect },
                    set: { newValue in
                        shares[index].autoConnect = newValue
                        persist()
                        if newValue { AutoConnector.shared.connectAll() }
                    }))
                Text("Reconnects when ShareMount starts, after the Mac wakes, and if the connection drops. Needs a saved password (below) unless the share allows guests.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let host = shares[index].host {
                    Divider().padding(.vertical, 4)
                    PasswordSection(host: host).id(host)
                }
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

/// Save, update or forget the Keychain password for a server. One password per
/// server, shared by every share on it.
private struct PasswordSection: View {
    let host: String

    @State private var savedUser: String?
    @State private var username = ""
    @State private var password = ""
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign-in for \(host)").font(.headline)

            if let savedUser {
                HStack {
                    Label("Password saved for “\(savedUser)”", systemImage: "key.fill")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Forget") {
                        KeychainStore.delete(server: host)
                        self.savedUser = nil
                        status = "Password removed."
                    }
                }
            }

            TextField("Username", text: $username)
            SecureField("Password", text: $password)
                .onSubmit(save)

            HStack {
                Button(savedUser == nil ? "Save Password" : "Update Password", action: save)
                    .disabled(username.isEmpty || password.isEmpty)
                if let status {
                    Text(status).font(.caption).foregroundColor(.secondary)
                }
            }

            Text("Stored in your Mac’s Keychain, never in ShareMount’s settings. It’s checked the next time the share connects.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            let saved = KeychainStore.load(server: host)
            savedUser = saved?.username
            username = saved?.username ?? ""
        }
    }

    private func save() {
        guard !username.isEmpty, !password.isEmpty else { return }
        KeychainStore.save(Credentials(username: username, password: password), server: host)
        savedUser = username
        password = ""
        status = "Saved."
    }
}

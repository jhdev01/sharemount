import SwiftUI

/// One drive's page in Settings.
struct DriveDetailView: View {

    let share: Share
    @ObservedObject var manager: ConnectionManager

    @State private var name: String
    @State private var savedUser: String?
    @State private var editingLocation = false
    @State private var editingPassword = false
    @State private var confirmingRemove = false

    init(share: Share, manager: ConnectionManager) {
        self.share = share
        _manager = ObservedObject(wrappedValue: manager)
        _name = State(initialValue: share.displayName)
    }

    private var state: DriveState { manager.state(of: share) }
    private var store: ShareStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Card {
                    HStack(spacing: 12) {
                        Text("Name").frame(width: 90, alignment: .leading).foregroundColor(.secondary)
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onChange(of: name) { newName in
                                store.mutate(share.id) { $0.displayName = newName }
                            }
                    }
                    .padding(12)
                    Divider()
                    HStack(spacing: 12) {
                        Text("Location").frame(width: 90, alignment: .leading).foregroundColor(.secondary)
                        Text(share.location.isEmpty ? "Not set" : share.location)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Change…") { editingLocation = true }
                    }
                    .padding(12)
                }

                Card {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Keep connected").font(.headline)
                            Text("Connects at login, after sleep, and whenever the connection drops.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("Keep connected", isOn: Binding(
                            get: { share.autoConnect },
                            set: { newValue in
                                store.mutate(share.id) { $0.autoConnect = newValue }
                                var updated = share
                                updated.autoConnect = newValue
                                manager.settingsChanged(for: updated)
                            }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(12)
                    Divider()
                    HStack(spacing: 12) {
                        Image(systemName: "key")
                            .foregroundColor(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            if let savedUser {
                                Text("Signed in as “\(savedUser)”").font(.headline)
                                Text("Password saved in your Keychain · used for every drive on \(share.computerName)")
                                    .font(.callout).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("No password saved").font(.headline)
                                Text("Connects as a guest, or with a password macOS already knows.")
                                    .font(.callout).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Button(savedUser == nil ? "Add Password…" : "Change…") { editingPassword = true }
                            .disabled(share.host == nil)
                    }
                    .padding(12)
                }

                HStack {
                    if case .connected(let path, _, _) = state {
                        Text("Mounted at \(path)").font(.callout).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Remove Drive…") { confirmingRemove = true }
                        .buttonStyle(.borderless)
                        .foregroundColor(Color(nsColor: .systemRed))
                }
            }
            .padding(24)
        }
        .onAppear(perform: loadSavedUser)
        .sheet(isPresented: $editingLocation) {
            LocationSheet(share: share)
        }
        .sheet(isPresented: $editingPassword, onDismiss: loadSavedUser) {
            if let host = share.host {
                PasswordSheet(host: host, computerName: share.computerName) {
                    manager.settingsChanged(for: share)
                }
            }
        }
        .confirmationDialog("Remove “\(share.displayName)”?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) { store.remove(share.id) }
        } message: {
            Text("It stays connected until you disconnect it, but won’t be reconnected again.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            StatusIcon(state: state, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(share.displayName.isEmpty ? "Untitled" : share.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.callout)
                    .foregroundColor(state == .off ? .secondary : Color(nsColor: state.tint))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch state {
            case .connected:
                Button("Open in Finder") { manager.openInFinder(share) }
                Button("Disconnect") { manager.disconnect(share) }
            case .connecting:
                ProgressView().controlSize(.small)
            case .needsPassword:
                Button("Sign In…") { editingPassword = true }
                    .buttonStyle(.borderedProminent)
            case .problem, .off:
                Button("Connect") { manager.connect(share) }
                    .buttonStyle(.borderedProminent)
            case .invalid:
                Button("Fix Location…") { editingLocation = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var statusLine: String {
        if case .connected(_, let free, let total) = state, total > 0 {
            let f = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            let t = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "Connected · \(f) free of \(t)"
        }
        return state.summary(for: share)
    }

    private func loadSavedUser() {
        savedUser = share.host.flatMap { KeychainStore.load(server: $0) }?.username
    }
}

/// Grouped box like System Settings.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

// MARK: - Sheets

private struct LocationSheet: View {
    let share: Share
    @Environment(\.dismiss) private var dismiss
    @State private var location: String

    init(share: Share) {
        self.share = share
        _location = State(initialValue: share.location)
    }

    private var isValid: Bool {
        Share(displayName: "", location: location).shareName != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change Location").font(.headline)
            TextField("smb://computer/drive", text: $location)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 380)
            Text("The computer’s name or address, then the shared folder or drive — for example smb://halderman-imac.local/5 TB or 192.168.1.20/Media.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 380, alignment: .leading)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    ShareStore.shared.mutate(share.id) { $0.location = location }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
    }
}

/// Add, change or forget the password for a computer.
struct PasswordSheet: View {
    let host: String
    let computerName: String
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var hasSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to \(computerName)").font(.headline)
            Text("Use an account on that computer. It’s saved in your Keychain and used for every drive on it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                if hasSaved {
                    Button("Forget Password", role: .destructive) {
                        KeychainStore.delete(server: host)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    KeychainStore.save(Credentials(username: username, password: password), server: host)
                    onSaved()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(username.isEmpty || password.isEmpty)
            }
        }
        .padding(20)
        .onAppear {
            let saved = KeychainStore.load(server: host)
            username = saved?.username ?? ""
            hasSaved = saved != nil
        }
    }
}

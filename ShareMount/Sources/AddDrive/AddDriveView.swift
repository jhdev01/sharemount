import SwiftUI

struct AddDriveView: View {

    @ObservedObject var browser: NetworkBrowser
    @StateObject private var model = AddDriveModel()
    let onDone: () -> Void

    @State private var selection: String?
    @State private var manualTarget: BrowseTarget?
    @State private var serverAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var keepConnected = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a Drive").font(.system(size: 17, weight: .bold))
                Text("Pick a computer, then tick the drives you want ShareMount to keep connected.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)
            Divider()

            HStack(spacing: 0) {
                sidebar.frame(width: 230)
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 480)
        .onChange(of: currentTarget) { model.load($0) }
    }

    // MARK: Computers

    private var currentTarget: BrowseTarget? {
        guard let selection else { return nil }
        if let manualTarget, manualTarget.id == selection { return manualTarget }
        guard let computer = browser.computers.first(where: { "bonjour:\($0.name)" == selection })
        else { return nil }
        return BrowseTarget(id: selection, title: computer.name, host: computer.host)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                Section("On your network") {
                    ForEach(browser.computers) { computer in
                        Label(computer.name, systemImage: "desktopcomputer")
                            .tag("bonjour:\(computer.name)")
                    }
                    if browser.isSearching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Looking for more…").foregroundColor(.secondary)
                        }
                    }
                }
                if let manualTarget {
                    Section("Typed address") {
                        Label(manualTarget.title, systemImage: "server.rack")
                            .tag(manualTarget.id)
                    }
                }
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 6) {
                Text("Or type an address")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TextField("192.168.1.20 or pc-name", text: $serverAddress)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(goToServer)
                    Button("Go", action: goToServer)
                        .disabled(serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(10)
        }
    }

    /// Accepts "192.168.1.20", "nas.local", "smb://nas/Media", "\\pc\share"...
    private func goToServer() {
        guard let host = Share(displayName: "", location: serverAddress).host else { return }
        let target = BrowseTarget(id: "manual:\(host)", title: host, host: host)
        manualTarget = target
        selection = target.id
        serverAddress = ""
    }

    // MARK: Drives

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            message("Choose a computer on the left. Macs with File Sharing on and most network drives appear automatically; for a Windows PC, type its name or address.")
        case .resolving:
            progress("Finding \(model.target?.title ?? "the computer")…")
        case .loading:
            progress("Asking \(model.target?.title ?? "the computer") what it shares…")
        case .failed(let text):
            VStack(spacing: 10) {
                Text(text).foregroundColor(.secondary).multilineTextAlignment(.center)
                Button("Try Again", action: model.reload)
            }
            .padding()
        case .needsSignIn(let text):
            signInForm(message: text)
        case .loaded(let names):
            if names.isEmpty {
                message("\(model.target?.title ?? "This computer") isn’t sharing any folders or drives with this account.")
            } else {
                driveChecklist(names)
            }
        }
    }

    private func driveChecklist(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .foregroundColor(Color(nsColor: .systemGreen))
                Text(model.signedInAs.map { "Signed in as “\($0)”" } ?? "Connected as a guest")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Use a different account…", action: model.switchAccount)
                    .buttonStyle(.link)
            }
            .font(.callout)

            Card {
                ForEach(Array(names.enumerated()), id: \.element) { index, name in
                    if index > 0 { Divider() }
                    checklistRow(name)
                }
            }

            Text("Don’t see a drive that’s plugged into that Mac? Share it there first: System Settings → General → Sharing → File Sharing, then add it under Shared Folders.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func checklistRow(_ name: String) -> some View {
        let added = model.isAdded(name)
        return Toggle(isOn: Binding(
            get: { added || model.selected.contains(name) },
            set: { on in
                if on { model.selected.insert(name) } else { model.selected.remove(name) }
            })) {
            HStack {
                Text(name).font(.system(size: 13, weight: .semibold))
                Spacer()
                if added {
                    Text("Already added").font(.callout).foregroundColor(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(added)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func signInForm(message text: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to \(model.target?.title ?? "this computer")").font(.headline)
            Text("Use an account on that computer. It’s saved in your Keychain.")
                .font(.caption)
                .foregroundColor(.secondary)
            if let text {
                Text(text).foregroundColor(Color(nsColor: .systemRed)).font(.callout)
            }
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(signIn)
            HStack {
                Spacer()
                Button("Sign In", action: signIn)
                    .keyboardShortcut(.defaultAction)
                    .disabled(username.isEmpty)
            }
        }
        .frame(maxWidth: 300)
        .padding()
        .onAppear {
            if username.isEmpty { username = model.savedUsername }
            password = ""
        }
    }

    private func signIn() {
        guard !username.isEmpty else { return }
        model.signIn(Credentials(username: username, password: password))
        password = ""
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)
            .padding()
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(text).foregroundColor(.secondary)
        }
    }

    // MARK: Footer

    private var addCount: Int {
        model.selected.filter { !model.isAdded($0) }.count
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("Keep these connected automatically", isOn: $keepConnected)
                .toggleStyle(.checkbox)
            Spacer()
            Button("Cancel", action: onDone)
                .keyboardShortcut(.cancelAction)
            Button(addCount == 1 ? "Add 1 Drive" : "Add \(addCount) Drives") {
                model.addSelected(keepConnected: keepConnected)
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(addCount == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

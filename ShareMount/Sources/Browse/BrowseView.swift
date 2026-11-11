import SwiftUI

struct BrowseView: View {

    @ObservedObject var browser: NetworkBrowser
    @StateObject private var model = ShareListModel()

    @State private var selection: String?
    @State private var manualTarget: BrowseTarget?
    @State private var serverAddress = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 200, idealWidth: 220, maxWidth: 300)
            detail.frame(minWidth: 340)
        }
        .frame(minWidth: 580, minHeight: 380)
        .onChange(of: currentTarget) { model.load($0) }
    }

    // MARK: Sidebar

    private var currentTarget: BrowseTarget? {
        guard let selection else { return nil }
        if let manualTarget, manualTarget.id == selection { return manualTarget }
        guard let computer = browser.computers.first(where: { "bonjour:\($0.name)" == selection })
        else { return nil }
        return BrowseTarget(id: selection, title: computer.name, host: computer.host)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section(header: searchingHeader) {
                    if browser.computers.isEmpty {
                        Text("No computers found yet")
                            .foregroundColor(.secondary)
                    }
                    ForEach(browser.computers) { computer in
                        Label(computer.name, systemImage: "desktopcomputer")
                            .tag("bonjour:\(computer.name)")
                    }
                }
                if let manualTarget {
                    Section(header: Text("Other")) {
                        Label(manualTarget.title, systemImage: "server.rack")
                            .tag(manualTarget.id)
                    }
                }
            }
            Divider()
            HStack(spacing: 6) {
                TextField("Server address", text: $serverAddress)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(goToServer)
                Button("Go", action: goToServer)
                    .disabled(serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
    }

    private var searchingHeader: some View {
        HStack(spacing: 6) {
            Text("Nearby")
            if browser.isSearching {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
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

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let target = model.target {
                HStack {
                    Text(target.title).font(.headline)
                    Spacer()
                    Button(action: model.reload) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Refresh")
                }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let notice = model.notice {
                Divider()
                Text(notice)
                    .font(.callout)
                    .foregroundColor(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            placeholder("Choose a computer, or type a server address below the list.")
        case .resolving:
            progress("Finding \(model.target?.title ?? "computer")…")
        case .loading:
            progress("Loading shared folders…")
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message).foregroundColor(.secondary).multilineTextAlignment(.center)
                Button("Try Again", action: model.reload)
            }
            .padding()
        case .needsSignIn(let message):
            signInForm(message: message)
        case .loaded(let shares):
            if shares.isEmpty {
                placeholder("This computer isn’t sharing any folders or drives with this account.")
            } else {
                shareList(shares)
            }
        }
    }

    private func shareList(_ shares: [String]) -> some View {
        List(shares, id: \.self) { name in
            HStack {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundColor(.secondary)
                Text(name)
                Spacer()
                if model.busyShares.contains(name) {
                    ProgressView().controlSize(.small)
                } else if model.mountPoint(of: name) != nil {
                    Button("Open") { model.reveal(name) }
                } else {
                    Button("Connect") { model.connect(name) }
                }
                if model.isInMenu(name) {
                    Label("In Menu", systemImage: "checkmark")
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)
                } else {
                    Button("Add to Menu") { model.addToMenu(name) }
                        .frame(width: 110, alignment: .leading)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func signInForm(message: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to \(model.target?.title ?? "this computer")")
                .font(.headline)
            Text("Use an account on that computer. It’s saved in your Keychain.")
                .font(.caption)
                .foregroundColor(.secondary)
            if let message {
                Text(message).foregroundColor(.red).font(.callout)
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

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(text).foregroundColor(.secondary)
        }
    }
}

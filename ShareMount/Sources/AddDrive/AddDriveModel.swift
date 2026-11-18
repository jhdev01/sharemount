import AppKit

/// The computer picked in Add a Drive.
struct BrowseTarget: Equatable {
    let id: String       // list selection tag
    let title: String    // what to show, e.g. "Halderman iMac"
    let host: String?    // nil while a Bonjour name is still resolving
}

/// Loads the drives a computer shares and turns the ticked ones into Shares.
final class AddDriveModel: ObservableObject {

    enum State: Equatable {
        case idle
        case resolving
        case loading
        /// `detail` is the system's own error text, shown small for diagnosis.
        case needsSignIn(message: String?, detail: String?)
        case loaded([String])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var target: BrowseTarget?
    /// Names of the drives ticked for adding.
    @Published var selected: Set<String> = []
    /// Who listed the drives (nil = guest).
    @Published private(set) var signedInAs: String?

    private var credentials: Credentials?
    private var generation = 0
    private let queue = DispatchQueue(label: "ShareMount.adddrive", qos: .userInitiated)

    func load(_ newTarget: BrowseTarget?) {
        generation += 1
        target = newTarget
        selected = []
        credentials = nil
        signedInAs = nil
        guard let newTarget else { state = .idle; return }
        guard let host = newTarget.host else { state = .resolving; return }
        list(host: host, credentials: KeychainStore.load(server: host), fromSignIn: false)
    }

    func reload() { load(target) }

    func signIn(_ credentials: Credentials) {
        guard let host = target?.host else { return }
        list(host: host, credentials: credentials, fromSignIn: true)
    }

    /// "Use a different account…"
    func switchAccount() {
        generation += 1
        state = .needsSignIn(message: nil, detail: nil)
    }

    var savedUsername: String {
        guard let host = target?.host else { return "" }
        return KeychainStore.load(server: host)?.username ?? ""
    }

    private func list(host: String, credentials: Credentials?, fromSignIn: Bool) {
        let current = generation
        state = .loading
        queue.async {
            let result = Result { try ShareLister.listShares(host: host, credentials: credentials) }
            DispatchQueue.main.async {
                guard current == self.generation else { return }   // selection changed
                switch result {
                case .success(let shares):
                    self.credentials = credentials
                    self.signedInAs = credentials?.username
                    if fromSignIn, let credentials { KeychainStore.save(credentials, server: host) }
                    // Pre-tick drives that aren't added yet when there's only one.
                    let addable = shares.filter { !self.isAdded($0) }
                    self.selected = addable.count == 1 ? Set(addable) : []
                    self.state = .loaded(shares)
                case .failure(let error):
                    if case ShareListError.authRequired(let detail)? = error as? ShareListError {
                        // Don't claim the password is wrong: smbutil can fail to sign
                        // in where Finder succeeds. Say what happened and offer ways on.
                        // A first visit with no password is normal: just ask. If a
                        // password was used (typed, or saved), say it failed and why.
                        let triedPassword = credentials != nil
                        self.state = .needsSignIn(
                            message: triedPassword ? "Couldn’t sign in to list the drives." : nil,
                            detail: triedPassword ? detail : nil)
                    } else {
                        self.state = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: Ways past a listing that won't sign in

    /// Let Finder sign in (its login works where smbutil's may not), then
    /// the user comes back and tries again.
    func openInFinder() {
        guard let host = target?.host, let url = URL(string: "smb://\(host)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Add a drive by typing its name, and connect it with these credentials.
    /// macOS's own connection (NetFS, as Finder uses) checks the password; if
    /// it works it's saved to the Keychain, otherwise the panel shows why.
    @discardableResult
    func addByName(_ rawName: String, credentials: Credentials?, keepConnected: Bool) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let target, let host = target.host, !name.isEmpty, !isAdded(name) else { return false }
        let share = Share(displayName: name, location: "smb://\(host)/\(name)",
                          autoConnect: keepConnected, serverName: target.title)
        guard share.shareName != nil else { return false }
        ShareStore.shared.add([share])
        ConnectionManager.shared.fillAwayHostsFromTailscale()
        ConnectionManager.shared.connect(share, credentials: credentials)
        return true
    }

    // MARK: Adding

    func isAdded(_ name: String) -> Bool {
        guard let host = target?.host else { return false }
        return ShareStore.shared.shares.contains { $0.refersTo(host: host, shareName: name) }
    }

    /// Save the ticked drives (and connect them if they should stay connected).
    /// Returns how many were added.
    @discardableResult
    func addSelected(keepConnected: Bool) -> Int {
        guard let target, let host = target.host else { return 0 }
        let names = selected.filter { !isAdded($0) }.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let shares = names.map {
            Share(displayName: $0, location: "smb://\(host)/\($0)",
                  autoConnect: keepConnected, serverName: target.title)
        }
        ShareStore.shared.add(shares)
        ConnectionManager.shared.fillAwayHostsFromTailscale()
        for share in shares where keepConnected {
            ConnectionManager.shared.connect(share, credentials: credentials)
        }
        selected = []
        return shares.count
    }
}

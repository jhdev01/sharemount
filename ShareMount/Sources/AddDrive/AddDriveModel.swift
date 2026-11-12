import Foundation

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
        case needsSignIn(message: String?)
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
        state = .needsSignIn(message: nil)
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
                case .failure(ShareListError.authRequired):
                    self.state = .needsSignIn(message: fromSignIn ? "The username or password was incorrect." : nil)
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
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
        for share in shares where keepConnected {
            ConnectionManager.shared.connect(share, credentials: credentials)
        }
        selected = []
        return shares.count
    }
}

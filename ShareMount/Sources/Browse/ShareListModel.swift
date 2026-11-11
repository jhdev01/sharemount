import AppKit

/// The computer selected in the Browse window.
struct BrowseTarget: Equatable {
    let id: String       // list selection tag
    let title: String    // what to show, e.g. "Joey's iMac"
    let host: String?    // nil while a Bonjour name is still resolving
}

/// Loads and acts on the shares of the selected computer.
final class ShareListModel: ObservableObject {

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
    @Published private(set) var busyShares: Set<String> = []
    @Published var notice: String?
    /// Bumped after a mount so rows re-check their connected state.
    @Published private(set) var refreshToken = 0

    /// The credentials that last listed shares successfully (nil = guest).
    private var credentials: Credentials?
    private var generation = 0
    private let queue = DispatchQueue(label: "ShareMount.browse", qos: .userInitiated)

    func load(_ newTarget: BrowseTarget?) {
        generation += 1
        target = newTarget
        notice = nil
        credentials = nil
        guard let newTarget else { state = .idle; return }
        guard let host = newTarget.host else { state = .resolving; return }
        list(host: host, credentials: KeychainStore.load(server: host), fromSignIn: false)
    }

    func signIn(_ credentials: Credentials) {
        guard let host = target?.host else { return }
        list(host: host, credentials: credentials, fromSignIn: true)
    }

    func reload() { load(target) }

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
                    if fromSignIn, let credentials { KeychainStore.save(credentials, server: host) }
                    self.state = .loaded(shares)
                case .failure(ShareListError.authRequired):
                    self.state = .needsSignIn(message: fromSignIn ? "The username or password was incorrect." : nil)
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: Share actions

    func share(named name: String) -> Share? {
        guard let target, let host = target.host else { return nil }
        return Share(displayName: "\(name) (\(target.title))", location: "smb://\(host)/\(name)")
    }

    func mountPoint(of name: String) -> String? {
        share(named: name).flatMap(MountManager.mountPoint(for:))
    }

    func isInMenu(_ name: String) -> Bool {
        guard let host = target?.host else { return false }
        return ShareStore.shared.shares.contains { $0.refersTo(host: host, shareName: name) }
    }

    func addToMenu(_ name: String) {
        guard !isInMenu(name), let share = share(named: name) else { return }
        ShareStore.shared.add(share)
        objectWillChange.send()
    }

    func connect(_ name: String) {
        guard let share = share(named: name), let host = share.host else { return }
        let credentials = self.credentials ?? KeychainStore.load(server: host)
        let current = generation
        busyShares.insert(name)
        notice = nil
        queue.async {
            let result = Result { try MountManager.mount(share, credentials: credentials) }
            DispatchQueue.main.async {
                self.busyShares.remove(name)
                guard current == self.generation else { return }
                switch result {
                case .success:
                    if let credentials { KeychainStore.save(credentials, server: host) }
                case .failure(MountError.authRequired):
                    self.state = .needsSignIn(message: "Sign in to connect to “\(name)”.")
                case .failure(let error):
                    self.notice = "Couldn’t connect to “\(name)”: \(error.localizedDescription)"
                }
                self.refreshToken += 1
            }
        }
    }

    func reveal(_ name: String) {
        guard let path = mountPoint(of: name) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

import AppKit
import Network

/// Keeps shares marked "Connect automatically" mounted: at launch, when the
/// network comes up, after the Mac wakes, and every couple of minutes in case
/// a connection dropped. Uses saved Keychain passwords and never prompts.
///
/// If you disconnect a share yourself, it's left alone until you connect it
/// again (or relaunch), so it doesn't fight you.
final class AutoConnector {

    static let shared = AutoConnector()

    /// Why the last automatic attempt failed, by share id. Main thread only.
    private(set) var lastErrors: [UUID: String] = [:]

    private var userDisconnected: Set<UUID> = []
    private var inFlight: Set<UUID> = []
    private var pending: DispatchWorkItem?
    private var timer: Timer?
    private let monitor = NWPathMonitor()
    // Concurrent: one unreachable server mustn't hold up the others.
    private let queue = DispatchQueue(label: "ShareMount.autoconnect", qos: .utility, attributes: .concurrent)

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            // Give DHCP/DNS/Bonjour a moment after the network appears.
            self?.schedule(after: 3)
        }
        monitor.start(queue: .main)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.schedule(after: 5)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.connectAll()
        }
        schedule(after: 1)
    }

    /// Call when the user disconnects a share from the menu.
    func userDidDisconnect(_ share: Share) {
        userDisconnected.insert(share.id)
    }

    /// Call when the user connects a share themselves.
    func userDidConnect(_ share: Share) {
        userDisconnected.remove(share.id)
        lastErrors[share.id] = nil
    }

    private func schedule(after seconds: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connectAll() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Try to mount every auto-connect share that isn't mounted. Main thread.
    func connectAll() {
        let shares = ShareStore.shared.shares.filter {
            $0.autoConnect && !userDisconnected.contains($0.id) && !inFlight.contains($0.id)
        }
        for share in shares {
            inFlight.insert(share.id)
            queue.async {
                let failure = Self.mountIfNeeded(share)
                DispatchQueue.main.async {
                    self.inFlight.remove(share.id)
                    self.lastErrors[share.id] = failure
                }
            }
        }
    }

    /// Returns nil on success (or if already mounted), else a message.
    private static func mountIfNeeded(_ share: Share) -> String? {
        if MountManager.isMounted(share) { return nil }
        let credentials = share.host.flatMap { KeychainStore.load(server: $0) }
        do {
            try MountManager.mount(share, credentials: credentials)
            return nil
        } catch MountError.authRequired {
            return credentials == nil
                ? "Couldn’t connect automatically: no saved password. Save one in Preferences."
                : "Couldn’t connect automatically: the saved password was rejected."
        } catch {
            return "Couldn’t connect automatically: \(error.localizedDescription)"
        }
    }
}

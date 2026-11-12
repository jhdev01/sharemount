import AppKit
import Combine
import Network

/// What a drive is doing right now, as shown in the panel and Settings.
enum DriveState: Equatable {
    case connected(mountPoint: String, freeBytes: Int64, totalBytes: Int64)
    case connecting
    /// Needs a (different) password. The message says which.
    case needsPassword(String)
    /// Last attempt failed for another reason (server asleep, offline...).
    case problem(String)
    /// Not connected and not trying (Keep connected is off, or the user
    /// disconnected it).
    case off
    /// The location can't be parsed.
    case invalid

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var needsAttention: Bool {
        switch self {
        case .needsPassword, .problem, .invalid: return true
        default: return false
        }
    }
}

/// Connects and disconnects drives and keeps the "Keep connected" ones
/// mounted: at launch, when the network comes up, after wake, and every
/// minute while one is down. Publishes each drive's `DriveState`.
///
/// If you disconnect a drive yourself it's left alone until you connect it
/// again (or relaunch), so it doesn't fight you.
final class ConnectionManager: ObservableObject {

    static let shared = ConnectionManager()
    static let retryInterval: TimeInterval = 60

    @Published private(set) var states: [Share.ID: DriveState] = [:]

    private enum Failure: Equatable {
        case auth(String)
        case other(String)
    }

    private var failures: [Share.ID: Failure] = [:]
    private var userDisconnected: Set<Share.ID> = []
    private var inFlight: Set<Share.ID> = []
    private var pending: DispatchWorkItem?
    private var retryTimer: Timer?
    private var refreshTimer: Timer?
    private var storeObserver: AnyCancellable?
    private let monitor = NWPathMonitor()
    // Concurrent: one unreachable server mustn't hold up the others.
    private let queue = DispatchQueue(label: "ShareMount.connect", qos: .userInitiated,
                                      attributes: .concurrent)

    private init() {}

    // MARK: Lifecycle

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            // Give DHCP/DNS/Bonjour a moment after the network appears.
            self?.scheduleAutoConnect(after: 3)
        }
        monitor.start(queue: .main)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleAutoConnect(after: 5)
        }
        // Mounts can also disappear (or appear, via Finder) behind our back.
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        }

        retryTimer = Timer.scheduledTimer(withTimeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            self?.autoConnectAll()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Async so the store has finished updating when we read it.
        storeObserver = ShareStore.shared.$shares
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }

        refresh()
        scheduleAutoConnect(after: 1)
    }

    private func scheduleAutoConnect(after seconds: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.autoConnectAll() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Status

    func state(of share: Share) -> DriveState {
        states[share.id] ?? .off
    }

    /// Recompute every drive's state from the kernel's mount table. Main thread.
    func refresh() {
        let mounts = MountManager.mountedVolumes()
        var newStates: [Share.ID: DriveState] = [:]
        for share in ShareStore.shared.shares {
            newStates[share.id] = computeState(share, mounts: mounts)
        }
        if newStates != states { states = newStates }
    }

    private func computeState(_ share: Share, mounts: [MountedVolume]) -> DriveState {
        guard share.host != nil, share.shareName != nil else { return .invalid }
        if let volume = mounts.first(where: { MountSource(mntFromName: $0.from)?.matches(share) == true }) {
            return .connected(mountPoint: volume.path, freeBytes: volume.freeBytes,
                              totalBytes: volume.totalBytes)
        }
        if inFlight.contains(share.id) { return .connecting }
        if userDisconnected.contains(share.id) { return .off }
        switch failures[share.id] {
        case .auth(let message)?: return .needsPassword(message)
        case .other(let message)?: return .problem(message)
        case nil: return .off
        }
    }

    // MARK: Actions

    /// Connect one drive. `credentials` (e.g. just typed) are saved to the
    /// Keychain if they work; otherwise the saved password is used.
    func connect(_ share: Share, credentials explicit: Credentials? = nil, userInitiated: Bool = true) {
        guard !inFlight.contains(share.id), share.shareName != nil else { return }
        if userInitiated { userDisconnected.remove(share.id) }
        inFlight.insert(share.id)
        refresh()

        queue.async {
            let credentials = explicit ?? share.host.flatMap { KeychainStore.load(server: $0) }
            var failure: Failure?
            if !MountManager.isMounted(share) {
                do {
                    try MountManager.mount(share, credentials: credentials)
                    if let explicit, let host = share.host {
                        KeychainStore.save(explicit, server: host)
                    }
                } catch MountError.authRequired {
                    failure = .auth(credentials == nil ? "Password needed" : "Password was rejected")
                } catch {
                    failure = .other(error.localizedDescription)
                }
            }
            DispatchQueue.main.async {
                self.inFlight.remove(share.id)
                self.failures[share.id] = failure
                self.refresh()
            }
        }
    }

    /// Ask for a username and password, then connect with them.
    func signIn(_ share: Share) {
        let saved = share.host.flatMap { KeychainStore.load(server: $0) }
        guard let credentials = CredentialPrompt.ask(for: share, prefillUser: saved?.username ?? "")
        else { return }
        connect(share, credentials: credentials)
    }

    func disconnect(_ share: Share) {
        userDisconnected.insert(share.id)
        failures[share.id] = nil
        queue.async {
            do {
                try MountManager.unmount(share)
            } catch {
                DispatchQueue.main.async {
                    // Usually "in use": a file on it is open somewhere.
                    self.userDisconnected.remove(share.id)
                    Self.alert("Couldn’t disconnect “\(share.displayName)”",
                               "Close any files or Finder windows using it and try again.\n\n\(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { self.refresh() }
        }
    }

    /// "Connect All" in the panel: every drive that isn't connected.
    func connectAll() {
        for share in ShareStore.shared.shares where !state(of: share).isConnected {
            connect(share)
        }
    }

    /// Background reconnect of Keep-connected drives. Never prompts.
    private func autoConnectAll() {
        refresh()
        for share in ShareStore.shared.shares
        where share.autoConnect && !userDisconnected.contains(share.id) && !state(of: share).isConnected {
            connect(share, userInitiated: false)
        }
    }

    /// Call after Keep connected is switched on, or a password is saved.
    func settingsChanged(for share: Share) {
        failures[share.id] = nil
        if share.autoConnect && !state(of: share).isConnected {
            connect(share)
        } else {
            refresh()
        }
    }

    func openInFinder(_ share: Share) {
        guard case .connected(let path, _, _) = state(of: share) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

// MARK: - Display helpers shared by the panel and Settings

extension DriveState {
    /// One-line description, e.g. "Connected · 3.2 TB free".
    func summary(for share: Share) -> String {
        switch self {
        case .connected(_, let free, _):
            return free > 0
                ? "Connected · \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free"
                : "Connected"
        case .connecting: return "Connecting…"
        case .needsPassword(let message): return message
        case .problem(let message):
            return share.autoConnect ? "\(message) Retrying automatically." : message
        case .off: return "Not connected"
        case .invalid: return "Location is incomplete"
        }
    }

    /// Accent colour for the status icon, dot and text.
    var tint: NSColor {
        switch self {
        case .connected: return .systemGreen
        case .connecting: return .systemBlue
        case .needsPassword, .invalid: return .systemRed
        case .problem: return .systemOrange
        case .off: return .secondaryLabelColor
        }
    }

    var symbolName: String {
        switch self {
        case .connected, .off: return "externaldrive"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .needsPassword: return "lock"
        case .problem: return "exclamationmark.arrow.triangle.2.circlepath"
        case .invalid: return "exclamationmark.triangle"
        }
    }
}

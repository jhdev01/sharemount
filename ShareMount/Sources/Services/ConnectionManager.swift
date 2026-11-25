import AppKit
import Combine
import Network

/// What a drive is doing right now, as shown in the panel and Settings.
enum DriveState: Equatable {
    /// `route` is nil when connected through the home address, else how it
    /// connected while away, e.g. "Tailscale".
    case connected(mountPoint: String, freeBytes: Int64, totalBytes: Int64, route: String?)
    case connecting
    /// Away from home and the away route (Tailscale) is switched off.
    case awayUnavailable(String)
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
        case .needsPassword, .problem, .invalid, .awayUnavailable: return true
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
    /// When the last automatic or manual check ran (shown in the panel).
    @Published private(set) var lastChecked: Date?

    private enum Failure: Equatable {
        case auth(String)
        case other(String)
        case awayUnavailable(String)
    }

    private var failures: [Share.ID: Failure] = [:]
    private var userDisconnected: Set<Share.ID> = []
    private var inFlight: Set<Share.ID> = []
    /// Drives whose connection is being checked for going stale.
    private var checkingStale: Set<Share.ID> = []
    /// Drives being moved to their other address (home <-> Tailscale): their
    /// brief disconnect isn't announced, only the reconnect.
    private var switchingRoute: Set<Share.ID> = []
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
            self?.replaceStaleMounts()
            self?.autoConnectAll()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Async so the store has finished updating when we read it.
        storeObserver = ShareStore.shared.$shares
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }

        Notifier.shared.onRetry = { [weak self] id in
            guard let self, let share = ShareStore.shared.shares.first(where: { $0.id == id }) else { return }
            self.connect(share)
        }

        refresh()
        fillAwayHostsFromTailscale()
        scheduleAutoConnect(after: 1)
    }

    /// A drive can stay "mounted" after the network changes even though its
    /// connection is dead (e.g. home Wi-Fi → phone hotspot), and then nothing
    /// would reconnect it. For each connected drive with an away address,
    /// check the address it's mounted through still answers; if it doesn't
    /// (twice) but the other address does, drop the dead mount and reconnect,
    /// which picks the working route. If neither answers (computer asleep or
    /// offline) the mount is left alone.
    private func replaceStaleMounts() {
        for share in ShareStore.shared.shares where share.autoConnect {
            guard case .connected(let path, _, _, let route) = state(of: share),
                  let homeHost = share.host, let awayHost = share.activeAwayHost,
                  !inFlight.contains(share.id), !checkingStale.contains(share.id),
                  !userDisconnected.contains(share.id)
            else { continue }
            checkingStale.insert(share.id)
            // Mark before unmounting: the unmount notification can arrive
            // before this check finishes, and shouldn't announce "Disconnected".
            switchingRoute.insert(share.id)
            let current = route == nil ? homeHost : awayHost
            let other = route == nil ? awayHost : homeHost
            queue.async {
                var dropped = false
                if !Reachability.canConnect(to: current) {
                    Thread.sleep(forTimeInterval: 1)
                    if !Reachability.canConnect(to: current), Reachability.canConnect(to: other) {
                        // The old connection is already dead; force it off so the
                        // drive can be mounted again through the working address.
                        dropped = Darwin.unmount(path, MNT_FORCE) == 0
                        NSLog("ShareMount: \(current) stopped answering, \(other) answers; " +
                              "dropped stale mount \(path): \(dropped)")
                    }
                }
                DispatchQueue.main.async {
                    self.checkingStale.remove(share.id)
                    guard dropped else {
                        self.switchingRoute.remove(share.id)
                        return
                    }
                    self.failures[share.id] = nil
                    self.refresh()
                    self.connect(share, userInitiated: false)
                }
            }
        }
    }

    /// The panel's refresh button: re-read every drive's status, then try
    /// every Keep-connected drive that's down, right now.
    func checkNow() {
        failures = failures.filter { _, failure in
            if case .auth = failure { return true }   // don't retry a known-bad password
            return false
        }
        fillAwayHostsFromTailscale()
        replaceStaleMounts()
        autoConnectAll()
    }

    /// Give drives with no away address yet (nil, not "") the Tailscale
    /// address of their computer, if Tailscale knows it.
    func fillAwayHostsFromTailscale() {
        let missing = ShareStore.shared.shares.filter { $0.awayHost == nil }
        guard !missing.isEmpty, TailscaleService.isInstalled else { return }
        queue.async {
            guard let status = TailscaleService.status() else { return }
            let found = missing.compactMap { share in
                status.awayHost(for: share).map { (share.id, $0) }
            }
            guard !found.isEmpty else { return }
            DispatchQueue.main.async {
                for (id, host) in found {
                    ShareStore.shared.mutate(id) { if $0.awayHost == nil { $0.awayHost = host } }
                }
            }
        }
    }

    private func scheduleAutoConnect(after seconds: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.replaceStaleMounts()
            self?.autoConnectAll()
        }
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
        notifyChanges(from: states, to: newStates)
        if newStates != states { states = newStates }
    }

    /// Notify when a drive becomes connected, or drops without the user
    /// disconnecting it. Drives seen for the first time (launch, just added
    /// while already mounted) don't notify.
    private func notifyChanges(from old: [Share.ID: DriveState], to new: [Share.ID: DriveState]) {
        for share in ShareStore.shared.shares {
            guard let before = old[share.id], let after = new[share.id] else { continue }
            if !before.isConnected, case .connected(_, _, _, let route) = after {
                switchingRoute.remove(share.id)
                Notifier.shared.driveConnected(share, via: route)
            } else if before.isConnected, !after.isConnected, !userDisconnected.contains(share.id) {
                if !switchingRoute.contains(share.id) {
                    Notifier.shared.driveLost(share, willRetry: share.autoConnect)
                }
                // Don't wait for the next one-minute retry.
                if share.autoConnect { scheduleAutoConnect(after: 2) }
            }
        }
    }

    private func computeState(_ share: Share, mounts: [MountedVolume]) -> DriveState {
        guard share.host != nil, share.shareName != nil else { return .invalid }
        for volume in mounts {
            guard let source = MountSource(mntFromName: volume.from), source.matches(share) else { continue }
            let route = source.isAway(for: share)
                ? share.activeAwayHost.map(Share.awayRouteName(for:)) : nil
            return .connected(mountPoint: volume.path, freeBytes: volume.freeBytes,
                              totalBytes: volume.totalBytes, route: route)
        }
        if inFlight.contains(share.id) { return .connecting }
        if userDisconnected.contains(share.id) { return .off }
        switch failures[share.id] {
        case .auth(let message)?: return .needsPassword(message)
        case .other(let message)?: return .problem(message)
        case .awayUnavailable(let message)?: return .awayUnavailable(message)
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
            // Passwords are saved under the home host and used for either route.
            let credentials = explicit ?? share.host.flatMap { KeychainStore.load(server: $0) }
            var failure: Failure?
            if !MountManager.isMounted(share) {
                failure = Self.mountByBestRoute(share, credentials: credentials)
                if failure == nil, let explicit, let host = share.host {
                    KeychainStore.save(explicit, server: host)
                }
            }
            DispatchQueue.main.async {
                self.inFlight.remove(share.id)
                self.failures[share.id] = failure
                if failure != nil { self.switchingRoute.remove(share.id) }
                self.refresh()
            }
        }
    }

    /// Try the home address and the away address (Tailscale), in the order a
    /// quick check suggests: home first if it answers, else away first. Both
    /// are always tried, because the quick check can miss (a waking computer,
    /// Local Network permission not granted yet). Returns nil on success.
    /// Runs on the background queue.
    private static func mountByBestRoute(_ share: Share, credentials: Credentials?) -> Failure? {
        guard let away = share.awayShare, let awayHost = share.activeAwayHost else {
            return attempt(share, credentials: credentials)          // no away address set
        }
        let homeAnswers = share.host.map { Reachability.canConnect(to: $0) } ?? false
        if homeAnswers {
            let failure = attempt(share, credentials: credentials)
            guard case .other? = failure else { return failure }    // done, or a password problem
            return attempt(away, credentials: credentials) == nil ? nil : failure
        }

        // Home didn't answer quickly: probably away. Try the away route first,
        // unless it's Tailscale and Tailscale is switched off.
        let route = Share.awayRouteName(for: awayHost)
        var tailscaleOff = false
        if route == "Tailscale", TailscaleService.isInstalled,
           let status = TailscaleService.status(), !status.isRunning {
            tailscaleOff = true
        }
        if !tailscaleOff {
            let awayFailure = attempt(away, credentials: credentials)
            guard case .other? = awayFailure else { return awayFailure }
        }
        // Then home anyway.
        let homeFailure = attempt(share, credentials: credentials)
        guard case .other(let message)? = homeFailure else { return homeFailure }
        if tailscaleOff { return .awayUnavailable("Away from home, and Tailscale is off") }
        return .other("Couldn’t reach it at home or via \(route). \(message)")
    }

    private static func attempt(_ share: Share, credentials: Credentials?) -> Failure? {
        do {
            try MountManager.mount(share, credentials: credentials)
            return nil
        } catch MountError.authRequired {
            return .auth(credentials == nil ? "Password needed" : "Password was rejected")
        } catch {
            return .other(error.localizedDescription)
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
        lastChecked = Date()
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
        guard case .connected(let path, _, _, _) = state(of: share) else { return }
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
        case .connected(_, let free, _, let route):
            let connected = route.map { "Connected via \($0)" } ?? "Connected"
            return free > 0
                ? "\(connected) · \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free"
                : connected
        case .connecting: return "Connecting…"
        case .awayUnavailable(let message): return message
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
        case .problem, .awayUnavailable: return .systemOrange
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
        case .awayUnavailable: return "wifi.exclamationmark"
        }
    }
}

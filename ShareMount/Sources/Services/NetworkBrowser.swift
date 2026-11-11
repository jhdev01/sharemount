import Foundation

/// A computer advertising SMB file sharing over Bonjour.
struct DiscoveredComputer: Identifiable, Equatable {
    /// Bonjour service name, e.g. "Joey's iMac".
    let name: String
    /// Resolved host name, e.g. "joeys-imac.local". Nil until resolved.
    var host: String?

    var id: String { name }
}

/// Finds computers on the local network that share files over SMB
/// (Macs with File Sharing on, most NAS boxes). Windows PCs usually don't
/// advertise over Bonjour, so they're reached by typing their address.
final class NetworkBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {

    @Published private(set) var computers: [DiscoveredComputer] = []
    @Published private(set) var isSearching = false

    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]

    /// Call on the main thread (the browser schedules on the current run loop).
    func start() {
        guard browser == nil else { return }
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        isSearching = true
        browser.searchForServices(ofType: "_smb._tcp.", inDomain: "local.")
    }

    func stop() {
        browser?.stop()
        browser = nil
        services.values.forEach { $0.stop() }
        services = [:]
        computers = []
        isSearching = false
    }

    // MARK: NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard services[service.name] == nil else { return }
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 10)
        computers.append(DiscoveredComputer(name: service.name, host: nil))
        computers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services[service.name]?.stop()
        services[service.name] = nil
        computers.removeAll { $0.name == service.name }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isSearching = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        NSLog("Bonjour search failed: \(errorDict)")
        isSearching = false
    }

    // MARK: NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName,
              let index = computers.firstIndex(where: { $0.name == sender.name })
        else { return }
        computers[index].host = Share.normalizedHost(hostName)
    }
}

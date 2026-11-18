import Foundation

/// The parts of `tailscale status --json` ShareMount uses. Kept free of
/// AppKit so it can be unit-tested.
struct TailscaleStatus: Decodable {
    struct Node: Decodable {
        var HostName: String?
        var DNSName: String?
        var TailscaleIPs: [String]?
        var Online: Bool?

        /// MagicDNS name without the trailing dot, else the IPv4 address.
        var address: String? {
            if let dns = DNSName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !dns.isEmpty {
                return dns.lowercased()
            }
            return TailscaleIPs?.first { $0.contains(".") }
        }

        /// Names this machine might go by, normalised for comparison.
        var nameKeys: Set<String> {
            var keys: Set<String> = []
            if let h = HostName { keys.insert(TailscaleStatus.key(h)) }
            if let d = DNSName, let first = d.split(separator: ".").first {
                keys.insert(TailscaleStatus.key(String(first)))
            }
            keys.remove("")
            return keys
        }
    }

    var BackendState: String?
    var Peer: [String: Node]?

    var isRunning: Bool { BackendState == "Running" }

    static func parse(_ data: Data) -> TailscaleStatus? {
        try? JSONDecoder().decode(TailscaleStatus.self, from: data)
    }

    /// Normalise a machine name: "Joey's iMac" / "joeys-imac" / "Joeys-iMac.local" → "joeys-imac".
    static func key(_ name: String) -> String {
        var n = name.lowercased()
        if n.hasSuffix(".local") { n.removeLast(".local".count) }
        n = n.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let mapped = n.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }

    /// The Tailscale address of the machine that serves `share`, matched by
    /// its .local host name or its friendly computer name.
    func awayHost(for share: Share) -> String? {
        var wanted: Set<String> = []
        if let host = share.host, Share.normalizedHost(host).hasSuffix(".local") {
            wanted.insert(Self.key(Share.normalizedHost(host)))
        }
        if let server = share.serverName { wanted.insert(Self.key(server)) }
        if share.host.map({ Share.normalizedHost($0).hasSuffix(".local") }) == true {
            wanted.insert(Self.key(share.computerName))
        }
        wanted.remove("")
        guard !wanted.isEmpty else { return nil }
        let match = (Peer ?? [:]).values
            .filter { !$0.nameKeys.isDisjoint(with: wanted) }
            .sorted { ($0.Online ?? false) && !($1.Online ?? false) }
            .first
        return match?.address
    }
}

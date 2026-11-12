import Foundation

/// A single configured network share: a friendly name plus an SMB location.
struct Share: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    /// What the user types, e.g. "smb://192.168.1.10/Media", "192.168.1.10/Media",
    /// "//nas/My Share" or "\\nas\Media".
    var location: String
    /// Mount automatically at launch, after wake, and if the connection drops.
    /// On by default: keeping drives mounted is the point of the app.
    var autoConnect: Bool

    init(id: UUID = UUID(), displayName: String, location: String, autoConnect: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.location = location
        self.autoConnect = autoConnect
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, location, autoConnect
    }

    /// Tolerates settings saved by older versions (no `autoConnect` key).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try c.decode(String.self, forKey: .displayName)
        location = try c.decode(String.self, forKey: .location)
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? true
    }

    /// Normalised `smb://` URL with the path percent-encoded (so share names
    /// containing spaces work), or nil if the location can't be parsed.
    var url: URL? {
        var raw = location.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        if raw.lowercased().hasPrefix("smb://") {
            raw.removeFirst("smb://".count)
        } else if raw.hasPrefix("//") {
            raw.removeFirst(2)
        }

        let parts = raw.split(separator: "/")
        guard let authority = parts.first, !authority.isEmpty else { return nil }

        // Decode first so text the user already percent-encoded isn't encoded twice.
        let path = parts.dropFirst().map { component -> String in
            let decoded = String(component).removingPercentEncoding ?? String(component)
            return decoded.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowed) ?? decoded
        }

        var string = "smb://\(authority)"
        if !path.isEmpty { string += "/" + path.joined(separator: "/") }
        return URL(string: string)
    }

    /// Host component, e.g. "192.168.1.10". Used as the Keychain server key.
    var host: String? {
        guard let host = url?.host, !host.isEmpty else { return nil }
        return host
    }

    /// Share name = first path component, decoded, e.g. "My Share". Used to match mounts.
    var shareName: String? {
        guard let path = url?.path else { return nil }
        return path.split(separator: "/").first.map(String.init)
    }

    /// True if this share points at `shareName` on `host` (same comparison
    /// rules as mount detection).
    func refersTo(host otherHost: String, shareName otherName: String) -> Bool {
        guard let host, let shareName else { return false }
        return Self.normalizedHost(host) == Self.normalizedHost(otherHost)
            && shareName.caseInsensitiveCompare(otherName) == .orderedSame
    }

    /// Canonical form of a host name for comparisons: lower-cased, no IPv6
    /// brackets or trailing dot, and Bonjour service names
    /// ("nas._smb._tcp.local") reduced to their plain ".local" name.
    static func normalizedHost(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        if h.hasSuffix(".") { h.removeLast() }
        h = h.replacingOccurrences(of: "._smb._tcp.local", with: ".local")
        return h
    }

    private static let pathComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;")
        return set
    }()
}

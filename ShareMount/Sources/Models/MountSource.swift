import Foundation

/// The host and share parsed out of an SMB mount's device name
/// (`statfs.f_mntfromname`), which looks like `//host/Share`,
/// `//user@host/Share`, or `//user@host/My%20Share/sub/folder`.
struct MountSource: Equatable {
    /// Normalised host (see `Share.normalizedHost`).
    let host: String
    /// Share name, percent-decoded.
    let shareName: String

    init?(mntFromName: String) {
        guard mntFromName.hasPrefix("//") else { return nil }
        let rest = mntFromName.dropFirst(2)
        guard let slash = rest.firstIndex(of: "/") else { return nil }

        // Authority: drop "user@" (and any "DOMAIN;" before it), then any ":port".
        var authority = rest[..<slash]
        if let at = authority.lastIndex(of: "@") {
            authority = authority[authority.index(after: at)...]
        }
        let hostPart: Substring
        if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
            hostPart = authority[...close]                       // IPv6 literal
        } else if let colon = authority.firstIndex(of: ":") {
            hostPart = authority[..<colon]
        } else {
            hostPart = authority
        }
        guard !hostPart.isEmpty else { return nil }

        let path = rest[rest.index(after: slash)...]
        guard let first = path.split(separator: "/").first else { return nil }

        let rawHost = String(hostPart)
        let rawShare = String(first)
        host = Share.normalizedHost(rawHost.removingPercentEncoding ?? rawHost)
        shareName = rawShare.removingPercentEncoding ?? rawShare
    }

    /// True if this mount is the given share (exact host, case-insensitive share name).
    func matches(_ share: Share) -> Bool {
        guard let shareHost = share.host, let name = share.shareName else { return false }
        return Share.normalizedHost(shareHost) == host
            && name.caseInsensitiveCompare(shareName) == .orderedSame
    }
}

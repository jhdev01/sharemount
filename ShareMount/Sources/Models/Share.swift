import Foundation

/// A single configured network share: a friendly name plus an SMB location.
struct Share: Codable, Identifiable, Equatable {
    var id = UUID()
    var displayName: String
    /// What the user types, e.g. "smb://192.168.1.10/Media" or "192.168.1.10/Media".
    var location: String

    /// Normalised `smb://` URL, or nil if the location can't be parsed.
    var url: URL? {
        var raw = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.lowercased().hasPrefix("smb://") {
            raw = raw.hasPrefix("//") ? "smb:\(raw)" : "smb://\(raw)"
        }
        return URL(string: raw)
    }

    /// Host component, e.g. "192.168.1.10". Used as the Keychain server key.
    var host: String? { url?.host }

    /// Share name = first path component, e.g. "Media". Used to match mounts.
    var shareName: String? {
        guard let path = url?.path else { return nil }
        return path.split(separator: "/").first.map(String.init)
    }
}

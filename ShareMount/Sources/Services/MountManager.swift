import Foundation
import NetFS
import AppKit

struct MountedVolume {
    let from: String   // device, e.g. "//user@host/Share"
    let path: String   // mountpoint, e.g. "/Volumes/Share"
}

enum MountError: Error {
    case invalidURL
    case authRequired       // bad or missing credentials
    case failed(Int32)      // some other NetFS status code
}

enum MountManager {

    // MARK: Detection

    /// Every filesystem currently mounted, read straight from the kernel.
    static func mountedVolumes() -> [MountedVolume] {
        var raw: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&raw, MNT_NOWAIT)
        guard count > 0, let buffer = raw else { return [] }

        var result: [MountedVolume] = []
        for i in 0..<Int(count) {
            var entry = buffer[i]
            result.append(
                MountedVolume(from: cString(&entry.f_mntfromname),
                              path: cString(&entry.f_mntonname))
            )
        }
        return result
    }

    /// The mountpoint for a share if it's currently mounted, else nil.
    /// SMB devices look like `//user@host/share` or `//host/share`, so we
    /// match on host + share name (case-insensitive).
    static func mountPoint(for share: Share) -> String? {
        guard let host = share.host?.lowercased(),
              let shareName = share.shareName?.lowercased()
        else { return nil }

        for volume in mountedVolumes() {
            let from = volume.from.lowercased()
            guard from.hasPrefix("//") else { continue }
            if from.contains(host) && from.hasSuffix("/\(shareName)") {
                return volume.path
            }
        }
        return nil
    }

    static func isMounted(_ share: Share) -> Bool {
        mountPoint(for: share) != nil
    }

    // MARK: Mount / unmount

    /// Synchronously mount the share. Blocks on the network — call off the main
    /// thread. Passing nil credentials lets NetFS fall back to the Keychain.
    static func mount(_ share: Share, credentials: Credentials?) throws {
        guard let url = share.url else { throw MountError.invalidURL }

        var mountpoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            url as CFURL,
            nil,                                 // default mount dir (/Volumes)
            credentials?.username as CFString?,
            credentials?.password as CFString?,
            nil,                                 // open options
            nil,                                 // mount options
            &mountpoints
        )
        mountpoints?.release()

        switch status {
        case 0:
            return
        case Int32(EAUTH), Int32(EACCES), Int32(EPERM):
            throw MountError.authRequired
        default:
            throw MountError.failed(status)
        }
    }

    /// Unmount (and eject) a currently mounted share. No-op if not mounted.
    static func unmount(_ share: Share) throws {
        guard let path = mountPoint(for: share) else { return }
        try NSWorkspace.shared.unmountAndEjectDevice(at: URL(fileURLWithPath: path))
    }

    // MARK: Helpers

    /// Read a fixed-size C char array (imported as a Swift tuple) into a String.
    private static func cString<T>(_ tuple: inout T) -> String {
        withUnsafePointer(to: &tuple) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }
}

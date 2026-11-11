import Foundation
import NetFS
import AppKit

struct MountedVolume {
    let from: String   // device, e.g. "//user@host/Share"
    let path: String   // mountpoint, e.g. "/Volumes/Share"
}

enum MountError: Error, LocalizedError {
    case invalidURL
    case authRequired       // bad or missing credentials
    case failed(Int32)      // some other NetFS status code

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The network location isn’t a valid SMB address."
        case .authRequired:
            return "The username or password was incorrect."
        case .failed(let code):
            return Self.message(for: code)
        }
    }

    /// Human-readable text for a NetFS / errno status code.
    static func message(for code: Int32) -> String {
        switch code {
        // NetFS-specific codes (see <NetFS/NetFS.h>).
        case -5045: return "The password has expired and must be changed."
        case -5046: return "The new password doesn’t meet the server’s password policy."
        case -5999: return "This account isn’t allowed to connect right now."
        case -5998: return "The server has no shares available to this account."
        case -5997: return "The server doesn’t support a compatible sign-in method."
        case -5996: return "The server doesn’t support a compatible SMB version."
        // Common POSIX codes, reworded for this context.
        case ENOENT: return "The share wasn’t found on the server. Check the share name."
        case EHOSTUNREACH, EHOSTDOWN: return "The server can’t be reached. Check that it’s on and on the same network."
        case ETIMEDOUT: return "The connection to the server timed out."
        case ECONNREFUSED: return "The server refused the connection. Check that file sharing (SMB) is turned on."
        case EEXIST: return "The share is already mounted."
        default:
            if code > 0, let text = strerror(code) {
                return "\(String(cString: text)) (error \(code))."
            }
            return "Unknown error (\(code))."
        }
    }
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
    /// Matches on exact host + share name (see `MountSource`).
    static func mountPoint(for share: Share) -> String? {
        for volume in mountedVolumes() {
            if let source = MountSource(mntFromName: volume.from), source.matches(share) {
                return volume.path
            }
        }
        return nil
    }

    static func isMounted(_ share: Share) -> Bool {
        mountPoint(for: share) != nil
    }

    // MARK: Mount / unmount

    // NetFS open-option key/value (kNAUIOptionKey / kNAUIOptionNoUI in
    // <NetFS/NetFS.h>). Suppresses the system's own login dialog so the app's
    // credential prompt is the only one the user sees.
    private static let uiOptionKey = "UIOption"
    private static let uiOptionNoUI = "NoUI"

    /// Synchronously mount the share. Blocks on the network — call off the main
    /// thread. Passing nil credentials lets NetFS fall back to the Keychain.
    static func mount(_ share: Share, credentials: Credentials?) throws {
        guard let url = share.url, share.host != nil, share.shareName != nil else {
            throw MountError.invalidURL
        }

        let openOptions = NSMutableDictionary()
        openOptions[uiOptionKey] = uiOptionNoUI

        var mountpoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            url as CFURL,
            nil,                                 // default mount dir (/Volumes)
            credentials?.username as CFString?,
            credentials?.password as CFString?,
            openOptions as CFMutableDictionary,
            nil,                                 // mount options
            &mountpoints
        )
        mountpoints?.release()

        switch status {
        case 0, Int32(EEXIST):      // EEXIST: already mounted — that's success too
            return
        case Int32(EAUTH), Int32(EACCES), Int32(EPERM), Int32(ENEEDAUTH):
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
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}

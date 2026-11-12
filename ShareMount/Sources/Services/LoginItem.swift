import Foundation
import ServiceManagement

/// Launch-at-login via the modern `SMAppService` API (macOS 13+).
///
/// The user's choice is remembered in UserDefaults (default: on), and the
/// registration is refreshed every launch from /Applications. That matters
/// because registering records *which copy* of the app to start: if it was
/// switched on while running from Xcode, login would start that old build
/// instead of the installed one.
enum LoginItem {

    private static let preferenceKey = "launchAtLogin"

    /// What the user asked for (on unless they've turned it off).
    static var isWanted: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS can require the user to allow the login item in System Settings.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Only the installed copy should register itself, never an Xcode build.
    static var isInstalledCopy: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// Call at launch: make the login item point at this (installed) copy.
    static func syncAtLaunch() {
        guard isInstalledCopy else { return }
        if isWanted {
            do { try SMAppService.mainApp.register() }   // re-registering is harmless
            catch { NSLog("LoginItem register: \(error.localizedDescription)") }
        } else if isEnabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("LoginItem error: \(error.localizedDescription)")
            return false
        }
    }
}

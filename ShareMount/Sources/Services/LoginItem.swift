import Foundation
import ServiceManagement

/// Launch-at-login via the modern `SMAppService` API (macOS 13+).
/// No helper bundle or deprecated `SMLoginItemSetEnabled` needed.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
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

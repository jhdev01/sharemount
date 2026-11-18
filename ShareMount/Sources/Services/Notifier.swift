import Foundation
import UserNotifications

/// macOS notifications when a drive connects, or drops without the user
/// disconnecting it. A dropped-drive notification has a Try Again button.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    static let shared = Notifier()

    private static let preferenceKey = "notifications"
    private static let lostCategory = "DRIVE_LOST"
    private static let retryAction = "RETRY"

    /// The user's choice in Settings → General (on unless turned off).
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: preferenceKey)
            if newValue { shared.requestPermission() }
        }
    }

    /// Called with the drive id when Try Again (or the notification) is clicked.
    var onRetry: ((Share.ID) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    /// Call at launch.
    func start() {
        center.delegate = self
        let retry = UNNotificationAction(identifier: Self.retryAction, title: "Try Again", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.lostCategory, actions: [retry],
                                   intentIdentifiers: [], options: [])
        ])
        if Self.isEnabled { requestPermission() }
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Notification permission: \(error.localizedDescription)") }
        }
    }

    func driveConnected(_ share: Share, via route: String?) {
        let body = route.map { "Connected via \($0)." } ?? "Connected."
        post(id: "connected-\(share.id)", title: share.displayName, body: body, share: share, lost: false)
    }

    func driveLost(_ share: Share, willRetry: Bool) {
        let body = willRetry
            ? "Disconnected. ShareMount will keep trying to reconnect."
            : "Disconnected."
        post(id: "lost-\(share.id)", title: share.displayName, body: body, share: share, lost: true)
    }

    private func post(id: String, title: String, body: String, share: Share, lost: Bool) {
        guard Self.isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["share": share.id.uuidString]
        if lost { content.categoryIdentifier = Self.lostCategory }
        // A newer notice for the same drive replaces the older one.
        center.removeDeliveredNotifications(withIdentifiers: ["connected-\(share.id)", "lost-\(share.id)"])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while ShareMount is the active app (e.g. panel open).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let isLost = response.notification.request.content.categoryIdentifier == Self.lostCategory
        if isLost, let raw = info["share"] as? String, let id = UUID(uuidString: raw) {
            // Try Again, or a click on the "disconnected" banner itself.
            DispatchQueue.main.async { self.onRetry?(id) }
        }
        completionHandler()
    }
}

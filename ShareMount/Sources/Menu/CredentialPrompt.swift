import Cocoa

/// A simple modal username/password prompt, shown the first time a share is
/// connected (or after a credential failure).
enum CredentialPrompt {

    /// Returns entered credentials, or nil if the user cancelled.
    static func ask(for share: Share, prefillUser: String = "") -> Credentials? {
        let alert = NSAlert()
        alert.messageText = "Connect to “\(share.displayName)”"
        alert.informativeText = "Enter the username and password for \(share.location)."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")

        let userField = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        userField.placeholderString = "Username"
        userField.stringValue = prefillUser

        let passField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        passField.placeholderString = "Password"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        container.addSubview(userField)
        container.addSubview(passField)
        alert.accessoryView = container
        alert.window.initialFirstResponder = userField.stringValue.isEmpty ? userField : passField

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return Credentials(username: userField.stringValue, password: passField.stringValue)
    }
}

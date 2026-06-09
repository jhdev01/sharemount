import Cocoa

// Programmatic entry point (no storyboard, no @main). Using a file literally
// named `main.swift` lets us run top-level code as the app's entry point.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

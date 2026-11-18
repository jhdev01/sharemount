import AppKit

/// Talks to the Tailscale app on this Mac (if installed) through its
/// command-line interface. Read-only: ShareMount never changes Tailscale.
enum TailscaleService {

    /// Where the Tailscale CLI lives: inside the Mac app (App Store or
    /// standalone), or a Homebrew/manual install.
    private static let cliPaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
    ]

    private static var cliPath: String? {
        cliPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { cliPath != nil }

    /// Current status, or nil if Tailscale isn't installed or didn't answer.
    /// Blocks for up to a few seconds — call off the main thread.
    static func status() -> TailscaleStatus? {
        guard let path = cliPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["status", "--json"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return nil
        }
        // Tailscale prints status even when stopped (exit code may be non-zero).
        return TailscaleStatus.parse(out.fileHandleForReading.readDataToEndOfFile())
    }

    /// Bring the Tailscale app forward so it can be switched on.
    static func open() {
        let url = URL(fileURLWithPath: "/Applications/Tailscale.app")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

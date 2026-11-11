import Foundation

enum ShareListError: Error, LocalizedError {
    case authRequired
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .authRequired: return "This computer needs a username and password."
        case .timedOut: return "The computer didn’t answer. It may be asleep or offline."
        case .failed(let message): return message
        }
    }
}

/// Lists the disk shares a server offers by running `smbutil view`.
/// macOS has no public API for this, and `smbutil` ships with every Mac.
enum ShareLister {

    /// Blocks on the network — call off the main thread.
    static func listShares(host: String, credentials: Credentials?) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        // -N: never prompt for a password on the terminal (there isn't one).
        process.arguments = ["view", "-N", SMBShareList.smbutilURL(host: host, credentials: credentials)]
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 20) == .timedOut {
            process.terminate()
            throw ShareListError.timedOut
        }

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        var errors = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            if let password = credentials?.password, !password.isEmpty {
                errors = errors.replacingOccurrences(of: password, with: "•••")
            }
            let lower = (errors + output).lowercased()
            if lower.contains("auth") || lower.contains("permission denied") || lower.contains("password") {
                throw ShareListError.authRequired
            }
            let message = errors.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShareListError.failed(message.isEmpty
                ? "Couldn’t list shares (smbutil exited with status \(process.terminationStatus))."
                : message)
        }
        return SMBShareList.diskShares(fromSmbutilOutput: output)
    }
}

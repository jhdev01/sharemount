import Foundation
import Network

enum Reachability {
    /// Whether a TCP connection to host:port opens within `timeout` seconds.
    /// Used to tell "at home" (the home address answers on SMB's port) from
    /// "away" quickly, instead of waiting out a full mount timeout.
    /// Blocks — call off the main thread.
    static func canConnect(to host: String, port: UInt16 = 445, timeout: TimeInterval = 2.5) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var ready = false
        var finished = false
        connection.stateUpdateHandler = { state in
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            switch state {
            case .ready:
                ready = true; finished = true; done.signal()
            case .failed, .cancelled, .waiting:
                finished = true; done.signal()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
        _ = done.wait(timeout: .now() + timeout)
        connection.cancel()
        lock.lock(); defer { lock.unlock() }
        return ready
    }

    /// Whether a mounted volume still answers: list its top folder on a
    /// separate thread and give up after `timeout`. A dead network mount
    /// hangs or fails here; a live one answers quickly. Blocks.
    static func mountResponds(at path: String, timeout: TimeInterval = 3) -> Bool {
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var answered = false
        Thread.detachNewThread {
            let ok = (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            lock.lock(); answered = ok; lock.unlock()
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else { return false }
        lock.lock(); defer { lock.unlock() }
        return answered
    }
}

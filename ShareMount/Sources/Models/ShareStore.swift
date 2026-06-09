import Foundation
import Combine

/// Single source of truth for the configured shares. Persists to UserDefaults.
/// The menu reads `shares` fresh every time it opens, so no change-observer is
/// needed there; SwiftUI Preferences observes it via `@Published`.
final class ShareStore: ObservableObject {
    static let shared = ShareStore()

    @Published private(set) var shares: [Share] = []

    private let key = "shares.v1"
    private let defaults = UserDefaults.standard

    private init() { load() }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Share].self, from: data)
        else {
            shares = []
            return
        }
        shares = decoded
    }

    /// Replace the whole list (Preferences edits a working copy and commits it).
    func replaceAll(_ newShares: [Share]) {
        shares = newShares
        if let data = try? JSONEncoder().encode(newShares) {
            defaults.set(data, forKey: key)
        }
    }
}

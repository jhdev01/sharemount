import Foundation
import Combine

/// Single source of truth for the configured shares. Persists to UserDefaults;
/// SwiftUI views observe it via `@Published`.
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

    func add(_ newShares: [Share]) {
        replaceAll(shares + newShares)
    }

    /// Replace the stored share that has the same id.
    func update(_ share: Share) {
        guard let index = shares.firstIndex(where: { $0.id == share.id }) else { return }
        var copy = shares
        copy[index] = share
        replaceAll(copy)
    }

    /// Edit one share in place: `ShareStore.shared.mutate(id) { $0.autoConnect = true }`.
    func mutate(_ id: Share.ID, _ change: (inout Share) -> Void) {
        guard var share = shares.first(where: { $0.id == id }) else { return }
        change(&share)
        update(share)
    }

    func remove(_ id: Share.ID) {
        replaceAll(shares.filter { $0.id != id })
    }
}

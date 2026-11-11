import Foundation
import Security

/// Stores SMB credentials as a standard internet-password Keychain item,
/// keyed by server host. Using `kSecAttrProtocolSMB` means these are the
/// same kind of items macOS itself creates for network shares.
enum KeychainStore {

    static func save(_ creds: Credentials, server: String) {
        // Remove any existing item for this server first, then add fresh.
        delete(server: server)
        var query = baseQuery(server: server)
        query[kSecAttrAccount as String] = creds.username
        query[kSecValueData as String] = Data(creds.password.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(server: String) -> Credentials? {
        var query = baseQuery(server: server)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let dict = item as? [String: Any],
              let account = dict[kSecAttrAccount as String] as? String,
              let data = dict[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }

        return Credentials(username: account, password: password)
    }

    static func delete(server: String) {
        SecItemDelete(baseQuery(server: server) as CFDictionary)
    }

    private static func baseQuery(server: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrProtocol as String: kSecAttrProtocolSMB,
            kSecAttrServer as String: server
        ]
    }
}

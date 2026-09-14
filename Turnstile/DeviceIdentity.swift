import Foundation
import Security

/// The only identity the app has: a random token kept in the keychain so a
/// reinstall keeps your history. It is not tied to you in any other way.
enum DeviceIdentity {
    private static let service = "tech.advancedfield.Turnstile"
    private static let account = "device-token"
    private static let earlierAccount = "player_id"   // TestFlight builds up to 7

    /// The existing token, or a new one saved for next time.
    static func current() -> String {
        if let token = read(account) { return token }
        if let carried = read(earlierAccount) {
            write(carried, to: account)
            return carried
        }
        let fresh = UUID().uuidString.lowercased()
        write(fresh, to: account)
        return fresh
    }

    /// Replace the token, e.g. after the player deletes their data.
    static func renew() -> String {
        let fresh = UUID().uuidString.lowercased()
        write(fresh, to: account)
        remove(earlierAccount)
        return fresh
    }

    private static func baseQuery(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: name]
    }

    private static func read(_ name: String) -> String? {
        var query = baseQuery(name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let data = found as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    private static func write(_ value: String, to name: String) {
        let changes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery(name) as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(name)
            for (k, v) in changes { item[k] = v }
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static func remove(_ name: String) {
        SecItemDelete(baseQuery(name) as CFDictionary)
    }
}

import Foundation
import Security

/// Stocke l'identifiant / mot de passe dans le Keychain (survit aux redémarrages de l'app).
enum CredentialStore {
    struct Credentials: Codable {
        let username: String
        let password: String
    }

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.masaison.credentials",
        kSecAttrAccount as String: "default",
        kSecUseDataProtectionKeychain as String: true,
    ]

    static func save(_ credentials: Credentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> Credentials? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

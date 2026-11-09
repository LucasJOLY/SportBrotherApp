import Foundation
import Security

/// Identifiant de ce téléphone, propriétaire de son profil Sport. Gardé dans le trousseau :
/// il survit à une réinstallation de l'app, contrairement aux réglages.
nonisolated enum DeviceIdentity {
    private static let service = "com.lucasjoly.SportBrother.device"
    private static let account = "owner"

    static let id: String = load() ?? create()

    private static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func create() -> String {
        let id = UUID().uuidString.lowercased()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(id.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
        return id
    }
}

import Foundation
import Security

/// Keychain-backed storage for provider API keys.
///
/// Secrets never go through `SettingsStore`: `UserDefaults` is a plist in the
/// user's Library that any process running as them can read.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = AppPaths.bundleIdentifier) {
        self.service = service
    }

    public func setSecret(_ secret: String?, for account: String) throws {
        guard let secret, !secret.isEmpty else {
            try removeSecret(for: account)
            return
        }
        guard let data = secret.data(using: .utf8) else {
            throw AnvilError.storage("Der Schlüssel konnte nicht kodiert werden.")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AnvilError.storage(Self.message(for: addStatus))
            }
            return
        }

        throw AnvilError.storage(Self.message(for: updateStatus))
    }

    public func secret(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func hasSecret(for account: String) -> Bool {
        secret(for: account)?.isEmpty == false
    }

    public func removeSecret(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AnvilError.storage(Self.message(for: status))
        }
    }

    private static func message(for status: OSStatus) -> String {
        let text = SecCopyErrorMessageString(status, nil) as String?
        return text ?? "Keychain-Fehler \(status)"
    }
}

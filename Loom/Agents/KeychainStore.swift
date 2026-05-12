import Foundation
import Security
import os

private let keychainLog = Logger(subsystem: "com.chasesims.LoomTestingEdition", category: "keychain")

enum KeychainStore {
    static let service = "com.chasesims.LoomTestingEdition"

    /// Stores `value` in the user's Keychain under (`service`, `account`).
    /// Items are scoped `WhenUnlockedThisDeviceOnly` so they never leak into an
    /// unencrypted iCloud Keychain backup or migrate to another device, and
    /// `Synchronizable: false` so iCloud Keychain is also opted out explicitly.
    /// Returns the OSStatus of the underlying SecItemAdd so callers can
    /// surface failures (disk full, locked Keychain, denied access).
    @discardableResult
    static func save(account: String, value: String) -> OSStatus {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrService as String:         service,
            kSecAttrAccount as String:         account,
            kSecAttrSynchronizable as String:  kCFBooleanFalse as Any
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            keychainLog.error("SecItemAdd failed for account \(account, privacy: .private): \(status, privacy: .public)")
        }
        return status
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainKey {
    static let anthropicAPIKey = "anthropic_api_key"
}


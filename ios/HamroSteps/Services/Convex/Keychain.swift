import Foundation
import Security

/// The few bytes the session keeps across launches. A protocol so tests use an
/// in-memory store.
///
/// `data(for:)` returns `nil` only when nothing is stored. A locked keychain
/// (a background launch before first unlock) throws instead, so a read
/// failure is never mistaken for "signed out".
protocol KeychainStoring: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}

struct KeychainError: Error, Hashable, Sendable {
    let status: OSStatus
}

/// Generic-password items in the app's keychain, readable after the first
/// unlock since boot, so a background HealthKit sync can refresh the session
/// while the phone is locked. Not synced to iCloud Keychain; an encrypted
/// backup restore keeps the person signed in.
struct SystemKeychain: KeychainStoring {
    var service = "com.bixustudio.hamrosteps.convex"

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func data(for key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    func set(_ data: Data, for key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query(key).merging(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

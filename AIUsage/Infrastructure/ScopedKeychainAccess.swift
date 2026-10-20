import Foundation
import Security

enum KeychainInteraction: Sendable {
    case silent
    case userInitiated
}

struct KeychainItemRevision: Equatable, Sendable {
    let reference: Data
    let modifiedAt: Date
}

/// Cache secrets only in memory. Checking attributes never requests the password
/// and still detects CLI sign-out, account changes, and credential rotation.
final class KeychainCredentialCache: @unchecked Sendable {
    private struct Item: Hashable {
        let service: String
        let account: String
    }
    private struct Entry {
        let revision: KeychainItemRevision
        let value: String
    }
    private let lock = NSLock()
    private var entries: [Item: Entry] = [:]

    func read(
        service: String, account: String,
        interaction: KeychainInteraction,
        keychain: any KeychainAccessing
    ) throws -> String? {
        try lock.withLock {
            let item = Item(service: service, account: account)
            guard let revision = try keychain.genericPasswordRevision(service: service, account: account) else {
                entries[item] = nil
                return nil
            }
            if let entry = entries[item], entry.revision == revision { return entry.value }
            entries[item] = nil
            guard let value = try keychain.readGenericPassword(
                service: service, account: account, interaction: interaction
            ) else { return nil }
            guard try keychain.genericPasswordRevision(service: service, account: account) == revision else {
                throw ProviderFailure(.storage, "The local login changed. Refresh to load the current session.")
            }
            entries[item] = Entry(revision: revision, value: value)
            return value
        }
    }
}

enum ScopedKeychainAccess {
    // Warp and Droid use the legacy file-based login Keychain. Its interaction
    // policy is process-wide, so serialize and restore it for every native call.
    // LAContext alone controls the newer data-protection Keychain, not these ACLs.
    private static let lock = NSLock()

    static func read(service: String, account: String, interaction: KeychainInteraction) throws -> String? {
        var query = query(service: service, account: account)
        query[kSecReturnData as String] = true
        guard let result = try copyMatching(query, interaction: interaction) else { return nil }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.readFailed
        }
        return value.isEmpty ? nil : value
    }

    static func revision(service: String, account: String) throws -> KeychainItemRevision? {
        var query = query(service: service, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnPersistentRef as String] = true
        guard let result = try copyMatching(query, interaction: .silent) else { return nil }
        guard let attributes = result as? [String: Any],
              let reference = attributes[kSecValuePersistentRef as String] as? Data,
              let modifiedAt = attributes[kSecAttrModificationDate as String] as? Date else {
            throw KeychainError.readFailed
        }
        return KeychainItemRevision(reference: reference, modifiedAt: modifiedAt)
    }

    private static func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecMatchLimit as String: kSecMatchLimitOne]
    }

    private static func copyMatching(_ query: [String: Any], interaction: KeychainInteraction) throws -> CFTypeRef? {
        try lock.withLock {
            var previous = DarwinBoolean(false)
            guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
                  SecKeychainSetUserInteractionAllowed(interaction == .userInitiated) == errSecSuccess else {
                throw KeychainError.readFailed
            }
            defer { _ = SecKeychainSetUserInteractionAllowed(previous.boolValue) }
            var result: CFTypeRef?
            switch SecItemCopyMatching(query as CFDictionary, &result) {
            case errSecSuccess: return result
            case errSecItemNotFound: return nil
            case errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed:
                throw KeychainError.interactionRequired
            default: throw KeychainError.readFailed
            }
        }
    }
}

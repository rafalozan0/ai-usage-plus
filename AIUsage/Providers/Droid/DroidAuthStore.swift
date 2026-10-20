import CryptoKit
import Foundation

struct DroidAuth: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let organizationID: String?
    let region: String?
    let path: String
    let encryptedText: String
    let key: Data
    let document: Data

    /// Stays the same when Droid rotates its tokens, and changes when a
    /// different user or organization signs in.
    var account: String {
        let user = ProviderParsing.string(ProviderParsing.jwtClaims(accessToken)?["sub"]) ?? refreshToken
        return "\(path)/\(organizationID ?? "")/\(user)"
    }
}

struct DroidAuthStore: Sendable {
    static let directory = "~/.factory/"
    let files: TextFileAccessing
    let keychain: KeychainAccessing
    private let cache = KeychainCredentialCache()

    init(files: TextFileAccessing = LocalTextFileAccessor(),
         keychain: KeychainAccessing = SecurityKeychainAccessor()) {
        self.files = files
        self.keychain = keychain
    }

    func load(interaction: KeychainInteraction = .silent) throws -> DroidAuth {
        let sources = [
            ("auth.v2.loginkeychain", "auth-encryption-key-security-cli"),
            ("auth.v2.keyring", "auth-encryption-key"),
            ("auth.v2.file", "")
        ]
        for (name, account) in sources {
            let path = Self.directory + name
            guard files.exists(path) else { continue }
            let encodedKey: String?
            if account.isEmpty {
                encodedKey = try files.readText(Self.directory + "auth.v2.key")
            } else {
                do {
                    encodedKey = try cache.read(service: "Factory CLI", account: account,
                                               interaction: interaction, keychain: keychain)
                } catch KeychainError.interactionRequired {
                    throw ProviderFailure(.keychainPermission,
                        "Droid's session is in the Keychain. Choose Always Allow so macOS doesn't ask again.")
                } catch {
                    throw ProviderFailure(.storage, "Droid credentials could not be read from the login Keychain.")
                }
            }
            guard let encodedKey,
                  let key = Data(base64Encoded: encodedKey.trimmingCharacters(in: .whitespacesAndNewlines)),
                  key.count == 32 else {
                throw ProviderFailure(.storage, "Unlock the login Keychain to read the Droid session.")
            }
            let encrypted = try files.readText(path)
            let document: Data
            do {
                document = try Self.decrypt(encrypted, key: key)
            } catch {
                throw ProviderFailure(.storage, "Droid credentials could not be decrypted. Sign in to Droid again.")
            }
            return try Self.auth(document: document, key: key, path: path, encryptedText: encrypted)
        }
        throw ProviderFailure(.authentication, "Not logged in. Run `droid` and sign in first.")
    }

    func saveRefresh(response: HTTPResponse, replacing original: DroidAuth) throws -> DroidAuth {
        let tokens = try ProviderParsing.object(from: response.body)
        guard let access = ProviderParsing.string(tokens["access_token"]),
              let refresh = ProviderParsing.string(tokens["refresh_token"]) else {
            throw ProviderFailure(.invalidResponse, "Droid returned an invalid session refresh.")
        }
        // Preserve organization, region, and fields added by future Droid versions.
        var document = try ProviderParsing.object(from: original.document)
        document["access_token"] = access
        document["refresh_token"] = refresh
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        let encrypted = try Self.encrypt(data, key: original.key)
        guard try load() == original else {
            throw ProviderFailure(.authentication, "Droid login changed. Refresh to load the current account.")
        }
        do {
            try files.writeText(original.path, encrypted)
        } catch {
            throw ProviderFailure(.storage, "Droid refreshed credentials could not be saved.")
        }
        return try Self.auth(document: data, key: original.key, path: original.path, encryptedText: encrypted)
    }

    private static func auth(document: Data, key: Data, path: String, encryptedText: String) throws -> DroidAuth {
        let body = try ProviderParsing.object(from: document)
        guard let access = ProviderParsing.string(body["access_token"]),
              let refresh = ProviderParsing.string(body["refresh_token"]) else {
            throw ProviderFailure(.authentication, "Droid session is incomplete. Run `droid` and sign in again.")
        }
        return DroidAuth(accessToken: access, refreshToken: refresh,
                         organizationID: ProviderParsing.string(body["active_organization_id"]),
                         region: ProviderParsing.string(body["region"]), path: path,
                         encryptedText: encryptedText, key: key, document: document)
    }

    static func decrypt(_ text: String, key: Data) throws -> Data {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let nonce = Data(base64Encoded: String(parts[0])), nonce.count == 16,
              let tag = Data(base64Encoded: String(parts[1])), tag.count == 16,
              let ciphertext = Data(base64Encoded: String(parts[2])) else {
            throw ProviderFailure(.storage, "Invalid Droid credential format.")
        }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    static func encrypt(_ data: Data, key: Data) throws -> String {
        // Droid's v2 storage uses a 16-byte nonce, rather than CryptoKit's default 12.
        let nonce = try AES.GCM.Nonce(data: Data((0..<16).map { _ in UInt8.random(in: 0...255) }))
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: key), nonce: nonce)
        return [Data(box.nonce), box.tag, box.ciphertext].map { $0.base64EncodedString() }.joined(separator: ":")
    }
}

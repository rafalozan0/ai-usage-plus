import Foundation

struct WarpAuth: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let service: String

    init(accessToken: String, refreshToken: String, service: String = WarpAuthStore.service) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.service = service
    }
}

struct WarpAuthStore: Sendable {
    static let service = "dev.warp.Warp-Stable"
    static let cliService = "dev.warp.Warp-Stable.tui"
    let keychain: KeychainAccessing
    private let cache = KeychainCredentialCache()

    init(keychain: KeychainAccessing = SecurityKeychainAccessor()) {
        self.keychain = keychain
    }

    func load(interaction: KeychainInteraction = .silent) throws -> WarpAuth {
        // The standalone Agent CLI has a separate Keychain namespace. Prefer
        // its active account over a potentially old desktop-app login.
        for service in [Self.cliService, Self.service] {
            let text: String?
            do {
                text = try cache.read(service: service, account: "User", interaction: interaction, keychain: keychain)
            } catch KeychainError.interactionRequired {
                throw ProviderFailure(.keychainPermission, "Allow Keychain access to read your Warp session.")
            } catch {
                throw ProviderFailure(.storage, "Allow access to the Warp session in the login Keychain, then refresh.")
            }
            guard let text else { continue }
            guard let data = text.data(using: .utf8),
                  let body = try? ProviderParsing.object(from: data),
                  let tokens = ProviderParsing.object(body["id_token"]),
                  let access = ProviderParsing.string(tokens["id_token"]),
                  let refresh = ProviderParsing.string(tokens["refresh_token"]) else {
                throw ProviderFailure(.authentication, "Warp session is incomplete. Sign in to Warp again.")
            }
            return WarpAuth(accessToken: access, refreshToken: refresh, service: service)
        }
        throw ProviderFailure(.authentication, "Not logged in. Sign in to Warp first.")
    }
}

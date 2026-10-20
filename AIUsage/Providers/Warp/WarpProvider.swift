import Foundation

actor WarpProvider: UsageProvider {
    nonisolated let id = ProviderID.warp
    private let authStore: WarpAuthStore
    private let client: WarpUsageClient
    private let dateProvider: DateProviding
    private var cachedAuth: WarpAuth?
    private var cachedLogin: WarpAuth?
    private var retryAt: Date?

    init(authStore: WarpAuthStore = WarpAuthStore(), client: WarpUsageClient = WarpUsageClient(),
         dateProvider: DateProviding = SystemDateProvider()) {
        self.authStore = authStore
        self.client = client
        self.dateProvider = dateProvider
    }

    func fetch() async throws -> ProviderSnapshot {
        let now = dateProvider.now()
        if let retryAt, retryAt > now {
            throw ProviderFailure(.rateLimited, "Warp is rate limited. Try again later.", retryAt: retryAt)
        }
        do {
            let login = try authStore.load()
            var auth = cachedLogin == login ? cachedAuth ?? login : login
            var refreshed = false
            if (ProviderParsing.jwtExpiration(auth.accessToken)?.timeIntervalSince(now) ?? 0) <= 300 {
                auth = try await refresh(auth)
                refreshed = true
            }
            var response = try await client.fetchUsage(accessToken: auth.accessToken)
            if !refreshed && (response.statusCode == 401 || response.statusCode == 403) {
                auth = try await refresh(auth)
                response = try await client.fetchUsage(accessToken: auth.accessToken)
            }
            let snapshot = try WarpUsageMapper.map(response: response, now: now)
            guard try authStore.load().account == login.account else {
                cachedAuth = nil
                cachedLogin = nil
                throw ProviderFailure(.authentication, "Warp login changed. Refresh to load the current account.")
            }
            cachedLogin = login
            cachedAuth = auth
            return snapshot
        } catch let failure as ProviderFailure {
            retryAt = failure.retryAt
            throw failure
        }
    }

    func authorizeKeychainAccess() async throws {
        _ = try authStore.load(interaction: .userInitiated)
    }

    private func refresh(_ auth: WarpAuth) async throws -> WarpAuth {
        let response = try await client.refreshToken(auth.refreshToken)
        // Firebase uses HTTP 400 for expired/revoked refresh credentials.
        if response.statusCode == 400 {
            throw ProviderFailure(.authentication, "Warp session expired. Sign in to Warp again.")
        }
        try ProviderParsing.requireSuccess(response, provider: "Warp", loginCommand: "warp", now: dateProvider.now())
        let body = try ProviderParsing.object(from: response.body)
        guard let token = ProviderParsing.string(body["id_token"]) else {
            throw ProviderFailure(.invalidResponse, "Warp returned an invalid session refresh.")
        }
        // Firebase refresh credentials remain reusable. Keep derived tokens in memory;
        // never overwrite the session owned by Warp.
        return WarpAuth(accessToken: token, refreshToken: ProviderParsing.string(body["refresh_token"]) ?? auth.refreshToken,
                        service: auth.service)
    }
}

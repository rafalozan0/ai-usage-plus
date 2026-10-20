import Foundation

actor DroidProvider: UsageProvider {
    nonisolated let id = ProviderID.droid
    private let authStore: DroidAuthStore
    private let client: DroidUsageClient
    private let dateProvider: DateProviding
    private var retryAt: Date?

    init(authStore: DroidAuthStore = DroidAuthStore(), client: DroidUsageClient = DroidUsageClient(),
         dateProvider: DateProviding = SystemDateProvider()) {
        self.authStore = authStore
        self.client = client
        self.dateProvider = dateProvider
    }

    func fetch() async throws -> ProviderSnapshot {
        let now = dateProvider.now()
        if let retryAt, retryAt > now {
            throw ProviderFailure(.rateLimited, "Droid is rate limited. Try again later.", retryAt: retryAt)
        }
        do {
            var auth = try authStore.load()
            var refreshed = false
            if (ProviderParsing.jwtExpiration(auth.accessToken)?.timeIntervalSince(now) ?? 0) <= 300 {
                auth = try await refresh(auth)
                refreshed = true
            }
            var response = try await client.fetchUsage(auth: auth)
            if !refreshed && (response.statusCode == 401 || response.statusCode == 403) {
                auth = try await refresh(auth)
                response = try await client.fetchUsage(auth: auth)
            }
            let snapshot = try DroidUsageMapper.map(response: response, now: now)
            guard try authStore.load() == auth else {
                throw ProviderFailure(.authentication, "Droid login changed. Refresh to load the current account.")
            }
            return snapshot
        } catch let failure as ProviderFailure {
            retryAt = failure.retryAt
            throw failure
        }
    }

    private func refresh(_ original: DroidAuth) async throws -> DroidAuth {
        let current = try authStore.load()
        guard current == original else { return current }
        let response = try await client.refreshToken(current.refreshToken)
        if response.statusCode == 400 {
            throw ProviderFailure(.authentication, "Droid session expired. Run `droid` and sign in again.")
        }
        try ProviderParsing.requireSuccess(response, provider: "Droid", loginCommand: "droid", now: dateProvider.now())
        return try authStore.saveRefresh(response: response, replacing: current)
    }

    func authorizeKeychainAccess() async throws {
        _ = try authStore.load(interaction: .userInitiated)
    }
}

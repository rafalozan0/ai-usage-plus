import XCTest
@testable import AIUsage

final class WarpAndDroidTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let key = Data(repeating: 7, count: 32)
    private let droidPath = "~/.factory/auth.v2.file"

    private var warpUsage: String {
        #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":false,"requestLimitRefreshDuration":"MONTHLY","requestLimit":1500,"requestsUsedSinceLastRefresh":375,"nextRefreshTime":"2027-02-01T00:00:00Z"}}}}}"#
    }

    private var droidUsage: String {
        #"{"limits":{"standard":{"fiveHour":{"usedPercent":12.5,"windowEnd":"2027-01-15T13:00:00Z"},"weekly":{"usedPercent":40,"windowEnd":1800000000000},"monthly":{"usedPercent":0,"windowEnd":null}},"core":{"fiveHour":{"usedPercent":3},"weekly":{"usedPercent":4},"monthly":{"usedPercent":5}}}}"#
    }

    func testWarpMapsMonthlyCreditsAndReset() throws {
        let snapshot = try WarpUsageMapper.map(response: httpResponse(json: warpUsage), now: now)
        XCTAssertEqual(snapshot.provider, .warp)
        XCTAssertEqual(snapshot.window(for: .monthly)?.usedPercent, 25)
        XCTAssertNotNil(snapshot.window(for: .monthly)?.resetsAt)
        XCTAssertEqual(snapshot.availableMenuBarItems.map(\.metric), [.monthly])
    }

    func testWarpPrefersDollarUsageWhenBothUnitsArePresent() throws {
        let json = warpUsage.replacingOccurrences(of: "\"requestLimit\":1500", with:
            "\"includedUsageCents\":2000,\"usageCentsUsedSinceLastRefresh\":1000,\"requestLimit\":1500")
        let snapshot = try WarpUsageMapper.map(response: httpResponse(json: json), now: now)
        XCTAssertEqual(snapshot.window(for: .monthly)?.usedPercent, 50)
    }

    func testWarpUsesTheReportedPeriod() throws {
        for (period, kind) in [("WEEKLY", QuotaKind.weekly), ("EVERY_TWO_WEEKS", .biweekly)] {
            let json = warpUsage.replacingOccurrences(of: "MONTHLY", with: period)
            let snapshot = try WarpUsageMapper.map(response: httpResponse(json: json), now: now)
            XCTAssertEqual(snapshot.windows.first?.kind, kind)
        }
        XCTAssertThrowsError(try WarpUsageMapper.map(response: httpResponse(json:
            warpUsage.replacingOccurrences(of: "MONTHLY", with: "UNKNOWN")), now: now))
    }

    func testWarpUnlimitedDoesNotInventAQuota() throws {
        let json = warpUsage.replacingOccurrences(of: "\"isUnlimited\":false", with: "\"isUnlimited\":true")
        let snapshot = try WarpUsageMapper.map(response: httpResponse(json: json), now: now)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.note, "Unlimited included usage")
    }

    func testWarpRejectsMissingCountsAndGraphQLErrors() {
        for json in ["{}", warpUsage.replacingOccurrences(of: "\"requestsUsedSinceLastRefresh\":375,", with: ""),
                     warpUsage.replacingOccurrences(of: "\"requestLimit\":1500", with: "\"requestLimit\":0"),
                     warpUsage.replacingOccurrences(of: "{\"data\"", with: "{\"errors\":[{\"message\":\"failure\"}],\"data\"")] {
            XCTAssertThrowsError(try WarpUsageMapper.map(response: httpResponse(json: json), now: now))
        }
    }

    func testWarpReadsOnlyTheUserKeychainAccount() throws {
        let auth = WarpAuthStore(keychain: warpKeychain(token: "access"))
        XCTAssertEqual(try auth.load(), WarpAuth(accessToken: "access", refreshToken: "refresh +&"))
        XCTAssertThrowsError(try WarpAuthStore(keychain: MemoryKeychain(generic: [
            WarpAuthStore.service: #"{"id_token":{"id_token":"wrong","refresh_token":"wrong"}}"#
        ])).load())
    }

    func testWarpPrefersTheCLISessionOverTheDesktopSession() throws {
        let store = WarpAuthStore(keychain: MemoryKeychain(accounts: [
            WarpAuthStore.cliService + "/User": #"{"id_token":{"id_token":"cli","refresh_token":"cli-refresh"}}"#,
            WarpAuthStore.service + "/User": #"{"id_token":{"id_token":"desktop","refresh_token":"desktop-refresh"}}"#
        ]))
        XCTAssertEqual(try store.load(), WarpAuth(accessToken: "cli", refreshToken: "cli-refresh", service: WarpAuthStore.cliService))
    }

    func testWarpRefreshIsCachedWithoutWritingWarpsLogin() async throws {
        let keychain = warpKeychain(token: jwt(expiration: now.timeIntervalSince1970 - 60))
        let http = MockHTTPClient([
            httpResponse(json: #"{"id_token":"\#(jwt(expiration: now.timeIntervalSince1970 + 3600))"}"#),
            httpResponse(json: warpUsage), httpResponse(json: warpUsage)
        ])
        let provider = WarpProvider(authStore: WarpAuthStore(keychain: keychain),
                                   client: WarpUsageClient(http: http), dateProvider: FixedDateProvider(value: now))
        _ = try await provider.fetch()
        _ = try await provider.fetch()
        let requests = await http.capturedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url.host, "securetoken.googleapis.com")
        XCTAssertTrue(String(data: requests[0].body!, encoding: .utf8)!.contains("refresh_token=refresh%20%2B%26"))
        XCTAssertEqual(requests[1].url.host, "app.warp.dev")
    }

    func testWarpHonorsCooldownOnManualRefresh() async {
        let http = MockHTTPClient([httpResponse(429, headers: ["Retry-After": "120"])])
        let provider = WarpProvider(authStore: WarpAuthStore(keychain: warpKeychain(
            token: jwt(expiration: now.timeIntervalSince1970 + 3600))),
            client: WarpUsageClient(http: http), dateProvider: FixedDateProvider(value: now))
        for _ in 0..<2 {
            do { _ = try await provider.fetch(); XCTFail("Expected rate limit") }
            catch let failure as ProviderFailure { XCTAssertEqual(failure.retryAt, now.addingTimeInterval(120)) }
            catch { XCTFail("Unexpected error") }
        }
        let count = await http.capturedRequests().count
        XCTAssertEqual(count, 1)
    }

    func testDroidMapsIndependentStandardAndCoreWindows() throws {
        let snapshot = try DroidUsageMapper.map(response: httpResponse(json: droidUsage), now: now)
        XCTAssertEqual(snapshot.provider, .droid)
        XCTAssertEqual(snapshot.windows.map(\.kind), [.session, .weekly, .monthly, .coreSession, .coreWeekly, .coreMonthly])
        XCTAssertEqual(snapshot.sessionWindow?.usedPercent, 12.5)
        XCTAssertEqual(snapshot.window(for: .weekly)?.resetsAt, now)
        XCTAssertNil(snapshot.window(for: .monthly)?.resetsAt)
        XCTAssertEqual(snapshot.menuBarValue(for: .coreWeekly, displayMode: .remaining), .percentage(96))
    }

    func testDroidOmitsAbsentWindowsWithoutInventingZeroUse() throws {
        let json = #"{"limits":{"standard":{"weekly":{"usedPercent":42}},"core":null}}"#
        let snapshot = try DroidUsageMapper.map(response: httpResponse(json: json), now: now)
        XCTAssertEqual(snapshot.windows.map(\.kind), [.weekly])
    }

    func testDroidRejectsMalformedWindows() {
        for json in ["{}", #"{"limits":{"standard":{}}}"#,
                     #"{"limits":{"standard":{"fiveHour":{"usedPercent":true}}}}"#,
                     #"{"limits":{"standard":{"fiveHour":{"usedPercent":-1}}}}"#,
                     #"{"limits":{"standard":{"fiveHour":{"usedPercent":5,"windowEnd":"invalid"}}}}"#] {
            XCTAssertThrowsError(try DroidUsageMapper.map(response: httpResponse(json: json), now: now))
        }
    }

    func testProviderFailuresPreserveLastGoodOnlyWhenAppropriate() {
        for (status, kind) in [(401, ProviderFailureKind.authentication), (403, .authentication),
                               (429, .rateLimited), (500, .transient), (400, .invalidResponse)] {
            for mapper in [WarpUsageMapper.map, DroidUsageMapper.map] {
                XCTAssertThrowsError(try mapper(httpResponse(status), now)) { error in
                    let failure = error as? ProviderFailure
                    XCTAssertEqual(failure?.kind, kind)
                    XCTAssertEqual(failure?.preservesLastGood, status != 401 && status != 403)
                }
            }
        }
    }

    func testDroidDecryptsCLICompatibleAESWith16ByteNonce() throws {
        // Fixed synthetic Node crypto AES-256-GCM fixture, independent of our encoder.
        let plaintext = Data(#"{"access_token":"access","refresh_token":"refresh"}"#.utf8)
        let encrypted = "AgICAgICAgICAgICAgICAg==:y4LS1Zv2/83s6BOSH7B9MQ==:p2yD+NfKLDoce2agomKLx9dYf9R/OhKuiR2oxdCjkQ+jdXETvMRGcuMeNsAP4sQUnO28"
        XCTAssertEqual(try DroidAuthStore.decrypt(encrypted, key: key), plaintext)
        XCTAssertThrowsError(try DroidAuthStore.decrypt(encrypted, key: Data(repeating: 8, count: 32)))
        XCTAssertThrowsError(try DroidAuthStore.decrypt("bad:data", key: key))
    }

    func testDroidReadsEncryptedFileAndKeychainStorage() throws {
        let files = try droidFiles()
        let original = try DroidAuthStore(files: files, keychain: MemoryKeychain()).load()
        XCTAssertEqual(original.organizationID, "org-test")
        XCTAssertEqual(original.region, "eu")
        for (file, account) in [("auth.v2.loginkeychain", "auth-encryption-key-security-cli"),
                                ("auth.v2.keyring", "auth-encryption-key")] {
            let store = DroidAuthStore(files: MemoryFiles(["~/.factory/" + file: original.encryptedText]),
                keychain: MemoryKeychain(accounts: ["Factory CLI/" + account: key.base64EncodedString()]))
            XCTAssertEqual(try store.load().accessToken, original.accessToken)
        }
    }

    func testDroidRefreshPreservesUnknownFieldsAndEncryption() throws {
        let files = try droidFiles()
        let store = DroidAuthStore(files: files, keychain: MemoryKeychain())
        let original = try store.load()
        let updated = try store.saveRefresh(response: httpResponse(json:
            #"{"access_token":"new-access","refresh_token":"new-refresh"}"#), replacing: original)
        XCTAssertEqual(try store.load(), updated)
        XCTAssertEqual(updated.organizationID, "org-test")
        XCTAssertEqual(updated.region, "eu")
        XCTAssertEqual(try ProviderParsing.object(from: updated.document)["future_field"] as? String, "keep")
        XCTAssertFalse(files.value(at: droidPath)!.contains("new-access"))
        XCTAssertNotEqual(original.encryptedText, updated.encryptedText)
    }

    func testDroidRefreshNeverOverwritesAConcurrentLogin() throws {
        let files = try droidFiles()
        let store = DroidAuthStore(files: files, keychain: MemoryKeychain())
        let original = try store.load()
        let changed = try DroidAuthStore.encrypt(Data(#"{"access_token":"other","refresh_token":"other"}"#.utf8), key: key)
        try files.writeText(droidPath, changed)
        XCTAssertThrowsError(try store.saveRefresh(response: httpResponse(json:
            #"{"access_token":"new-access","refresh_token":"new-refresh"}"#), replacing: original))
        XCTAssertEqual(files.value(at: droidPath), changed)
    }

    func testDroidRefreshRetriesOnceAndUsesTheActiveEUOrganization() async throws {
        let files = try droidFiles()
        let newToken = jwt(expiration: now.timeIntervalSince1970 + 7200)
        let http = MockHTTPClient([httpResponse(401), httpResponse(json:
            #"{"access_token":"\#(newToken)","refresh_token":"rotated"}"#), httpResponse(json: droidUsage)])
        let store = DroidAuthStore(files: files, keychain: MemoryKeychain())
        let provider = DroidProvider(authStore: store, client: DroidUsageClient(http: http),
                                    dateProvider: FixedDateProvider(value: now))
        _ = try await provider.fetch()
        let requests = await http.capturedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url.host, "api.eu.factory.ai")
        XCTAssertEqual(requests[0].headers["X-Factory-Org-Id"], "org-test")
        XCTAssertEqual(requests[1].url, DroidUsageClient.refreshURL)
        XCTAssertEqual(requests[2].headers["Authorization"], "Bearer \(newToken)")
        XCTAssertEqual(try store.load().refreshToken, "rotated")
    }

    func testDroidCooldownSkipsASecondRequest() async throws {
        let http = MockHTTPClient([httpResponse(429, headers: ["Retry-After": "60"])])
        let provider = DroidProvider(authStore: DroidAuthStore(files: try droidFiles(), keychain: MemoryKeychain()),
                                    client: DroidUsageClient(http: http), dateProvider: FixedDateProvider(value: now))
        for _ in 0..<2 {
            do { _ = try await provider.fetch(); XCTFail("Expected rate limit") }
            catch let failure as ProviderFailure { XCTAssertEqual(failure.retryAt, now.addingTimeInterval(60)) }
        }
        let count = await http.capturedRequests().count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testNewProvidersAreMigratedOnceAndRespectLaterOptOuts() throws {
        let suite = "WarpAndDroidTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([ProviderID.codex]), forKey: "trackedProviderIDs.v1")
        defaults.set(true, forKey: "openUsageProvidersAdded.v1")
        let first = AppPreferences(defaults: defaults)
        XCTAssertEqual(first.trackedProviderIDs, [.codex, .warp, .droid])
        XCTAssertEqual(AppPreferences(defaults: defaults).trackedProviderIDs, [.codex, .warp, .droid])
        first.setTracking(false, for: .warp)
        XCTAssertEqual(AppPreferences(defaults: defaults).trackedProviderIDs, [.codex, .droid])
    }

    private func warpKeychain(token: String) -> MemoryKeychain {
        MemoryKeychain(accounts: [WarpAuthStore.service + "/User":
            #"{"id_token":{"id_token":"\#(token)","refresh_token":"refresh +&"}}"#])
    }

    private func droidFiles() throws -> MemoryFiles {
        let document = Data(#"{"access_token":"\#(jwt(expiration: now.timeIntervalSince1970 + 3600))","refresh_token":"refresh","active_organization_id":"org-test","region":"eu","future_field":"keep"}"#.utf8)
        return MemoryFiles([droidPath: try DroidAuthStore.encrypt(document, key: key),
                            "~/.factory/auth.v2.key": key.base64EncodedString()])
    }
}

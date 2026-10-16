import XCTest
@testable import AIUsage

private struct StubXSubscriptionPool: XSubscriptionPoolReading {
    let pool: XSubscriptionPool?

    func fetchXSubscriptionPool() async -> XSubscriptionPool? { pool }
}

final class XSubscriptionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCursorLabelsMergedAccountsAsTheSharedXSubscriptionPool() throws {
        let snapshot = try CursorUsageMapper.map(
            usageResponse: httpResponse(json: """
            {
              "enabled": true,
              "billingCycleEnd": "1800100000000",
              "planUsage": {"totalPercentUsed": 18, "autoPercentUsed": 18, "apiPercentUsed": 0}
            }
            """),
            planResponse: httpResponse(json: """
            {
              "planInfo": {
                "planName": "Plus",
                "includedUsagePeriod": "INCLUDED_USAGE_PERIOD_WEEKLY"
              },
              "isMerged": true
            }
            """),
            now: now
        )

        XCTAssertEqual(snapshot.planName, "X Plus")
        XCTAssertEqual(snapshot.note, CursorUsageMapper.xSubscriptionNote)
    }

    func testCursorKeepsStandalonePlansUnchanged() throws {
        let snapshot = try CursorUsageMapper.map(
            usageResponse: httpResponse(json: """
            {"enabled": true, "planUsage": {"totalPercentUsed": 10}}
            """),
            planResponse: httpResponse(json: """
            {"planInfo": {"planName": "Pro"}}
            """),
            now: now
        )

        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertNil(snapshot.note)
    }

    func testGrokShowsTheSharedPoolWhenXAIBillingFails() async throws {
        let reset = now.addingTimeInterval(3 * 86_400)
        let http = MockHTTPClient([
            httpResponse(500, json: #"{"error":"Failed to serialize billing response"}"#),
            httpResponse(json: #"{"subscription_tier_display":"SuperGrok Lite"}"#)
        ])
        let provider = GrokProvider(
            authStore: grokAuthStore(),
            client: GrokUsageClient(http: http),
            xSubscriptionPool: StubXSubscriptionPool(pool: XSubscriptionPool(
                tierName: "Plus",
                usedPercent: 18,
                resetsAt: reset
            )),
            dateProvider: FixedDateProvider(value: now)
        )

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.provider, .grok)
        XCTAssertEqual(snapshot.planName, "X Plus")
        XCTAssertEqual(snapshot.windows.map(\.kind), [.weekly])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [18])
        XCTAssertEqual(snapshot.windows.first?.resetsAt, reset)
        XCTAssertEqual(snapshot.note, GrokUsageMapper.xSubscriptionNote)
    }

    func testGrokExplainsTheOutageWithoutASharedPool() async {
        let http = MockHTTPClient([
            httpResponse(500, json: #"{"error":"Failed to serialize billing response"}"#),
            httpResponse(json: "{}")
        ])
        let provider = GrokProvider(
            authStore: grokAuthStore(),
            client: GrokUsageClient(http: http),
            xSubscriptionPool: StubXSubscriptionPool(pool: nil),
            dateProvider: FixedDateProvider(value: now)
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected a failure")
        } catch let failure as ProviderFailure {
            XCTAssertEqual(failure.kind, .transient)
            XCTAssertEqual(
                failure.message,
                "xAI isn't reporting Grok usage right now (500)."
            )
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testGrokPrefersItsOwnWeeklyQuotaWhenAvailable() async throws {
        let http = MockHTTPClient([
            httpResponse(json: """
            {
              "config": {
                "creditUsagePercent": 40,
                "currentPeriod": {
                  "type": "USAGE_PERIOD_TYPE_WEEKLY",
                  "end": "2027-01-15T00:00:00Z"
                }
              }
            }
            """),
            httpResponse(json: #"{"subscription_tier_display":"SuperGrok"}"#)
        ])
        let provider = GrokProvider(
            authStore: grokAuthStore(),
            client: GrokUsageClient(http: http),
            xSubscriptionPool: StubXSubscriptionPool(pool: XSubscriptionPool(
                tierName: "Plus",
                usedPercent: 90,
                resetsAt: nil
            )),
            dateProvider: FixedDateProvider(value: now)
        )

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.planName, "SuperGrok")
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [40])
        XCTAssertNil(snapshot.note)
    }

    private func grokAuthStore() -> GrokAuthStore {
        GrokAuthStore(
            files: MemoryFiles([
                GrokAuthStore.authPath: """
                {"user::client": {"key": "access", "refresh_token": "refresh"}}
                """
            ]),
            dateProvider: FixedDateProvider(value: now)
        )
    }
}

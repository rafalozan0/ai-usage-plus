import Foundation

enum WarpUsageMapper {
    static func map(response: HTTPResponse, now: Date) throws -> ProviderSnapshot {
        try ProviderParsing.requireSuccess(response, provider: "Warp", loginCommand: "warp", now: now)
        let body = try ProviderParsing.object(from: response.body)
        guard ProviderParsing.array(body["errors"]).isEmpty,
              let data = ProviderParsing.object(body["data"]),
              let result = ProviderParsing.object(data["user"]),
              let user = ProviderParsing.object(result["user"]),
              let limit = ProviderParsing.object(user["requestLimitInfo"]) else {
            throw ProviderFailure(.invalidResponse, "Warp quota response changed.")
        }
        if limit["isUnlimited"] as? Bool == true {
            return ProviderSnapshot(provider: .warp, planName: nil, windows: [],
                                    note: "Unlimited included usage", fetchedAt: now)
        }
        let kind: QuotaKind
        switch ProviderParsing.string(limit["requestLimitRefreshDuration"]) {
        case "MONTHLY": kind = .monthly
        case "WEEKLY": kind = .weekly
        case "EVERY_TWO_WEEKS": kind = .biweekly
        default: throw ProviderFailure(.invalidResponse, "Warp returned an unknown quota period.")
        }

        // Dollar-billed plans expose cents; legacy plans expose credits.
        let dollarLimit = ProviderParsing.double(limit["includedUsageCents"])
        let dollarUsage = ProviderParsing.double(limit["usageCentsUsedSinceLastRefresh"])
        let usesDollars = dollarLimit != nil && dollarUsage != nil
        guard let total = usesDollars ? dollarLimit : ProviderParsing.double(limit["requestLimit"]),
              let used = usesDollars ? dollarUsage : ProviderParsing.double(limit["requestsUsedSinceLastRefresh"]),
              total > 0, used >= 0, (used / total * 100).isFinite else {
            throw ProviderFailure(.invalidResponse, "Warp isn't reporting a finite included allowance.")
        }
        return ProviderSnapshot(
            provider: .warp, planName: nil,
            windows: [QuotaWindow(kind: kind, usedPercent: used / total * 100,
                                  resetsAt: ProviderParsing.date(limit["nextRefreshTime"]))],
            note: usesDollars ? "Included usage · shared with Warp CLI"
                : "Included credits · shared with Warp CLI",
            fetchedAt: now
        )
    }
}

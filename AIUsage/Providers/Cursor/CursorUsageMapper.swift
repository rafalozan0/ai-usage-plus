import Foundation

enum CursorUsageMapper {
    static let xSubscriptionNote = String(localized: "X Subscription pool, shared with Grok")

    struct PlanInfo: Equatable {
        let name: String
        /// True when the Cursor account is part of The X Subscription, whose
        /// weekly pool is shared with Grok.
        let isXSubscription: Bool

        var displayName: String {
            isXSubscription ? "X \(name)" : name
        }
    }

    static func map(
        usageResponse: HTTPResponse,
        planResponse: HTTPResponse?,
        now: Date
    ) throws -> ProviderSnapshot {
        guard (200..<300).contains(usageResponse.statusCode) else {
            throw ProviderFailure(
                usageResponse.statusCode >= 500
                    ? .transient
                    : .invalidResponse,
                "Cursor usage request failed (\(usageResponse.statusCode))."
            )
        }
        let body = try ProviderParsing.object(
            from: usageResponse.body
        )
        guard body["enabled"] as? Bool != false,
              let planUsage = ProviderParsing.object(body["planUsage"])
        else {
            throw ProviderFailure(
                .authentication,
                "No active Cursor subscription."
            )
        }

        let reset = ProviderParsing.date(body["billingCycleEnd"])
        var windows: [QuotaWindow] = []
        if let percent = totalPercent(planUsage) {
            windows.append(QuotaWindow(
                kind: .totalUsage,
                usedPercent: clamp(percent),
                resetsAt: reset
            ))
        }
        if let percent = ProviderParsing.double(
            planUsage["autoPercentUsed"]
        ) {
            windows.append(QuotaWindow(
                kind: .autoUsage,
                usedPercent: clamp(percent),
                resetsAt: reset
            ))
        }
        if let percent = ProviderParsing.double(
            planUsage["apiPercentUsed"]
        ) {
            windows.append(QuotaWindow(
                kind: .apiUsage,
                usedPercent: clamp(percent),
                resetsAt: reset
            ))
        }
        guard !windows.isEmpty else {
            throw ProviderFailure(
                .invalidResponse,
                "Cursor quota response changed."
            )
        }

        let plan = planInfo(planResponse)
        return ProviderSnapshot(
            provider: .cursor,
            planName: plan?.displayName,
            windows: windows,
            note: plan?.isXSubscription == true ? xSubscriptionNote : nil,
            fetchedAt: now
        )
    }

    private static func totalPercent(
        _ planUsage: [String: Any]
    ) -> Double? {
        if let reported = ProviderParsing.double(
            planUsage["totalPercentUsed"]
        ) {
            return reported
        }
        guard let limit = ProviderParsing.double(planUsage["limit"]),
              limit > 0 else {
            return nil
        }
        let spent = ProviderParsing.double(planUsage["totalSpend"])
            ?? (limit - (
                ProviderParsing.double(planUsage["remaining"]) ?? limit
            ))
        return spent / limit * 100
    }

    static func planInfo(_ response: HTTPResponse?) -> PlanInfo? {
        guard let response,
              (200..<300).contains(response.statusCode),
              let body = try? ProviderParsing.object(
                from: response.body
              ),
              let info = ProviderParsing.object(body["planInfo"]),
              let name = ProviderParsing.string(info["planName"])
        else {
            return nil
        }
        return PlanInfo(
            name: name,
            isXSubscription: body["isMerged"] as? Bool == true
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

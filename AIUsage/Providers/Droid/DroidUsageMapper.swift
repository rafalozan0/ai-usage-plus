import Foundation

enum DroidUsageMapper {
    static func map(response: HTTPResponse, now: Date) throws -> ProviderSnapshot {
        try ProviderParsing.requireSuccess(response, provider: "Droid", loginCommand: "droid", now: now)
        let body = try ProviderParsing.object(from: response.body)
        guard let limits = ProviderParsing.object(body["limits"]),
              let standard = ProviderParsing.object(limits["standard"]) else {
            throw ProviderFailure(.invalidResponse, "Droid quota response changed.")
        }
        let standardWindows = try windows(standard, kinds: [.session, .weekly, .monthly])
        guard !standardWindows.isEmpty else {
            throw ProviderFailure(.invalidResponse, "Droid isn't reporting Standard Usage limits.")
        }
        let core = ProviderParsing.object(limits["core"])
        let coreWindows = try core.map { try windows($0, kinds: [.coreSession, .coreWeekly, .coreMonthly]) } ?? []
        return ProviderSnapshot(provider: .droid, planName: nil, windows: standardWindows + coreWindows,
                                note: "Standard Usage and Droid Core have separate limits.", fetchedAt: now)
    }

    private static func windows(_ pool: [String: Any], kinds: [QuotaKind]) throws -> [QuotaWindow] {
        try zip(["fiveHour", "weekly", "monthly"], kinds).compactMap { key, kind in
            guard let value = pool[key], !(value is NSNull) else { return nil }
            guard let window = ProviderParsing.object(value),
                  let used = ProviderParsing.double(window["usedPercent"]), used >= 0 else {
                throw ProviderFailure(.invalidResponse, "Droid returned an unreadable \(kind.title) limit.")
            }
            let reset = window["windowEnd"]
            let date = ProviderParsing.date(reset)
            guard reset == nil || reset is NSNull || date != nil else {
                throw ProviderFailure(.invalidResponse, "Droid returned an unreadable reset time.")
            }
            return QuotaWindow(kind: kind, usedPercent: used, resetsAt: date)
        }
    }
}

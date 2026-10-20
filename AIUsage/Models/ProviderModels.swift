import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case cursor
    case antigravity
    case copilot
    case devin
    case grok
    case deepseek
    case warp
    case droid

    var id: Self { self }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        case .copilot: "GitHub Copilot"
        case .devin: "Devin"
        case .grok: "Grok"
        case .deepseek: "DeepSeek"
        case .warp: "Warp"
        case .droid: "Droid (Factory)"
        }
    }

    var iconAssetName: String {
        switch self {
        case .claude: "ProviderClaude"
        case .codex: "ProviderCodex"
        case .cursor: "ProviderCursor"
        case .antigravity: "ProviderAntigravity"
        case .copilot: "ProviderCopilot"
        case .devin: "ProviderDevin"
        case .grok: "ProviderGrok"
        case .deepseek: "ProviderDeepSeek"
        case .warp: "ProviderWarp"
        case .droid: "ProviderDroid"
        }
    }

    var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: self,
            displayName: displayName,
            iconAssetName: iconAssetName,
            executableNames: executableNames,
            installationIndicators: installationIndicators,
            defaultMenuBarMetric: defaultMenuBarMetric
        )
    }

    private var executableNames: [String] {
        switch self {
        case .claude: ["claude"]
        case .codex: ["codex"]
        case .cursor: ["cursor"]
        case .antigravity: ["antigravity", "agy"]
        case .copilot: ["copilot", "github-copilot"]
        case .devin: ["devin"]
        case .grok: ["grok"]
        case .deepseek: []
        case .warp: ["warp"]
        case .droid: ["droid"]
        }
    }

    private var installationIndicators: [String] {
        switch self {
        case .claude:
            ["~/.claude", "~/.config/claude"]
        case .codex:
            ["~/.codex", "~/.config/codex"]
        case .cursor:
            [
                "/Applications/Cursor.app",
                "~/Applications/Cursor.app",
                "~/Library/Application Support/Cursor"
            ]
        case .antigravity:
            [
                "/Applications/Antigravity.app",
                "~/Applications/Antigravity.app",
                "~/Library/Application Support/Antigravity"
            ]
        case .copilot:
            [
                "~/.config/github-copilot/apps.json",
                "~/.config/github-copilot/hosts.json"
            ]
        case .devin:
            [
                "~/.local/share/devin",
                "/Applications/Devin.app",
                "~/Applications/Devin.app",
                "~/Library/Application Support/Devin"
            ]
        case .grok:
            ["~/.grok"]
        case .deepseek:
            // Detected by the presence of a stored API key instead.
            []
        case .warp:
            ["~/.warp", "~/.warp_cli", "/Applications/Warp.app", "~/Applications/Warp.app"]
        case .droid:
            ["~/.factory"]
        }
    }

    var defaultMenuBarMetric: MenuBarMetricID {
        switch self {
        case .cursor: .totalUsage
        case .copilot: .credits
        case .deepseek: .credits
        case .warp: .monthly
        case .claude, .codex, .antigravity, .devin, .grok, .droid: .weekly
        }
    }
}

enum QuotaKind: String, Codable, Hashable, Sendable {
    case biweekly
    case monthly
    case coreSession
    case coreWeekly
    case coreMonthly
    case session
    case weekly
    case daily
    case sonnet
    case fable
    case sparkSession
    case sparkWeekly
    case totalUsage
    case autoUsage
    case apiUsage
    case credits
    case chat
    case completions
    case claudePool
    case claudePoolWeekly
    case argonWeekly

    var title: String {
        switch self {
        case .biweekly: String(localized: "Two Weeks")
        case .monthly: String(localized: "Monthly")
        case .coreSession: String(localized: "Core Session")
        case .coreWeekly: String(localized: "Core Weekly")
        case .coreMonthly: String(localized: "Core Monthly")
        case .session: String(localized: "Session")
        case .weekly: String(localized: "Weekly")
        case .daily: String(localized: "Daily")
        case .sonnet: String(localized: "Sonnet")
        case .fable: String(localized: "Fable")
        case .sparkSession: String(localized: "Spark")
        case .sparkWeekly: String(localized: "Spark Weekly")
        case .totalUsage: String(localized: "Total Usage")
        case .autoUsage: String(localized: "Auto Usage")
        case .apiUsage: String(localized: "API Usage")
        case .credits: String(localized: "Credits")
        case .chat: String(localized: "Chat")
        case .completions: String(localized: "Completions")
        case .claudePool: String(localized: "Claude")
        case .claudePoolWeekly: String(localized: "Claude Weekly")
        case .argonWeekly: String(localized: "Argon Weekly")
        }
    }

    /// The allowance this window draws from. Windows from different pools
    /// never share a row in the provider card.
    var pool: QuotaPool {
        switch self {
        case .coreSession, .coreWeekly, .coreMonthly: .droidCore
        case .sparkSession, .sparkWeekly: .spark
        case .claudePool, .claudePoolWeekly: .claude
        case .argonWeekly: .argon
        case .biweekly, .monthly, .session, .weekly, .daily, .sonnet, .fable,
             .totalUsage, .autoUsage, .apiUsage, .credits, .chat, .completions:
            .standard
        }
    }

    var menuBarMetric: MenuBarMetricID {
        switch self {
        case .biweekly: .biweekly
        case .monthly: .monthly
        case .coreSession: .coreSession
        case .coreWeekly: .coreWeekly
        case .coreMonthly: .coreMonthly
        case .session: .session
        case .weekly: .weekly
        case .daily: .daily
        case .sonnet: .sonnet
        case .fable: .fable
        case .sparkSession: .spark
        case .sparkWeekly: .sparkWeekly
        case .totalUsage: .totalUsage
        case .autoUsage: .autoUsage
        case .apiUsage: .apiUsage
        case .credits: .credits
        case .chat: .chat
        case .completions: .completions
        case .claudePool: .claudePool
        case .claudePoolWeekly: .claudePoolWeekly
        case .argonWeekly: .argonWeekly
        }
    }
}

enum QuotaPool: Hashable, Sendable {
    case standard
    case spark
    case claude
    case argon
    case droidCore
}

enum MenuBarMetricID: String, CaseIterable, Codable, Identifiable, Sendable {
    case biweekly
    case monthly
    case coreSession
    case coreWeekly
    case coreMonthly
    case session
    case weekly
    case daily
    case sonnet
    case fable
    case spark
    case sparkWeekly
    case totalUsage
    case autoUsage
    case apiUsage
    case chat
    case completions
    case claudePool
    case claudePoolWeekly
    case argonWeekly
    case extraUsage
    case credits

    var id: Self { self }

    var title: String {
        switch self {
        case .biweekly: String(localized: "Two Weeks")
        case .monthly: String(localized: "Monthly")
        case .coreSession: String(localized: "Core Session")
        case .coreWeekly: String(localized: "Core Weekly")
        case .coreMonthly: String(localized: "Core Monthly")
        case .session: String(localized: "Session")
        case .weekly: String(localized: "Weekly")
        case .daily: String(localized: "Daily")
        case .sonnet: String(localized: "Sonnet")
        case .fable: String(localized: "Fable")
        case .spark: String(localized: "Spark")
        case .sparkWeekly: String(localized: "Spark Weekly")
        case .totalUsage: String(localized: "Total Usage")
        case .autoUsage: String(localized: "Auto Usage")
        case .apiUsage: String(localized: "API Usage")
        case .chat: String(localized: "Chat")
        case .completions: String(localized: "Completions")
        case .claudePool: String(localized: "Claude")
        case .claudePoolWeekly: String(localized: "Claude Weekly")
        case .argonWeekly: String(localized: "Argon Weekly")
        case .extraUsage: String(localized: "Extra Usage")
        case .credits: String(localized: "Credits")
        }
    }

    var systemImage: String {
        switch self {
        case .biweekly: "calendar"
        case .monthly, .coreMonthly: "calendar"
        case .coreSession: "clock"
        case .coreWeekly: "calendar.badge.clock"
        case .session: "clock"
        case .weekly: "calendar"
        case .daily: "sun.max"
        case .sonnet: "waveform"
        case .fable: "book.closed"
        case .spark: "sparkles"
        case .sparkWeekly: "calendar.badge.clock"
        case .totalUsage: "gauge.with.dots.needle.50percent"
        case .autoUsage: "wand.and.sparkles"
        case .apiUsage: "terminal"
        case .chat: "bubble.left.and.bubble.right"
        case .completions: "text.badge.checkmark"
        case .claudePool: "brain"
        case .claudePoolWeekly: "calendar.badge.clock"
        case .argonWeekly: "atom"
        case .extraUsage: "dollarsign.circle"
        case .credits: "creditcard"
        }
    }

    var compactLabel: String {
        switch self {
        case .biweekly: "2W"
        case .monthly: "M"
        case .coreSession: "CS"
        case .coreWeekly: "CW"
        case .coreMonthly: "CM"
        case .session: "S"
        case .weekly: "W"
        case .daily: "D"
        case .sonnet: "So"
        case .fable: "F"
        case .spark: "Sp"
        case .sparkWeekly: "SpW"
        case .totalUsage: "T"
        case .autoUsage: "A"
        case .apiUsage: "API"
        case .chat: "Ch"
        case .completions: "Co"
        case .claudePool: "Cl"
        case .claudePoolWeekly: "ClW"
        case .argonWeekly: "ArW"
        case .extraUsage: "E"
        case .credits: "C"
        }
    }

    var quotaKind: QuotaKind? {
        switch self {
        case .biweekly: .biweekly
        case .monthly: .monthly
        case .coreSession: .coreSession
        case .coreWeekly: .coreWeekly
        case .coreMonthly: .coreMonthly
        case .session: .session
        case .weekly: .weekly
        case .daily: .daily
        case .sonnet: .sonnet
        case .fable: .fable
        case .spark: .sparkSession
        case .sparkWeekly: .sparkWeekly
        case .totalUsage: .totalUsage
        case .autoUsage: .autoUsage
        case .apiUsage: .apiUsage
        case .chat: .chat
        case .completions: .completions
        case .claudePool: .claudePool
        case .claudePoolWeekly: .claudePoolWeekly
        case .argonWeekly: .argonWeekly
        case .credits: .credits
        case .extraUsage: nil
        }
    }
}

struct MenuBarItemID: Codable, Hashable, Identifiable, Sendable {
    let provider: ProviderID
    let metric: MenuBarMetricID

    var id: String { "\(provider.rawValue).\(metric.rawValue)" }
    var title: String { "\(provider.displayName) · \(metric.title)" }
}

struct MenuBarProviderConfiguration:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    let provider: ProviderID
    let metrics: [MenuBarMetricID]

    var id: ProviderID { provider }
}

struct ProviderDescriptor: Identifiable, Sendable {
    let id: ProviderID
    let displayName: String
    let iconAssetName: String
    let executableNames: [String]
    let installationIndicators: [String]
    let defaultMenuBarMetric: MenuBarMetricID
}

enum ProviderCatalog {
    static let all = ProviderID.allCases.map(\.descriptor)

    static func descriptor(for provider: ProviderID) -> ProviderDescriptor {
        provider.descriptor
    }
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    let kind: QuotaKind
    let usedPercent: Double
    let resetsAt: Date?

    var id: QuotaKind { kind }
    var renderedFraction: Double { min(max(usedPercent / 100, 0), 1) }
}

enum BillingUsage: Equatable, Sendable {
    case boundedSpend(
        usedAmount: Double,
        limitAmount: Double,
        currencyCode: String
    )
    case unboundedSpend(
        usedAmount: Double,
        currencyCode: String
    )
    case flexCreditBalance(
        remainingCredits: Int,
        usdValue: Double
    )
    case balance(
        amount: Double,
        currencyCode: String
    )

    var menuBarMetric: MenuBarMetricID {
        switch self {
        case .boundedSpend, .unboundedSpend: .extraUsage
        case .flexCreditBalance, .balance: .credits
        }
    }

    func menuBarValue(
        displayMode: UsageDisplayMode
    ) -> MenuBarReadingValue {
        switch self {
        case let .boundedSpend(usedAmount, limitAmount, currencyCode):
            let amount = displayMode == .used
                ? usedAmount
                : max(limitAmount - usedAmount, 0)
            return .money(amount: amount, currencyCode: currencyCode)
        case let .unboundedSpend(usedAmount, currencyCode):
            return .money(amount: usedAmount, currencyCode: currencyCode)
        case let .balance(amount, currencyCode):
            return .money(amount: amount, currencyCode: currencyCode)
        case let .flexCreditBalance(remainingCredits, usdValue):
            return .credits(
                remaining: remainingCredits,
                usdValue: usdValue
            )
        }
    }
}

enum MenuBarReadingValue: Equatable, Sendable {
    case percentage(Double)
    case money(amount: Double, currencyCode: String)
    case credits(remaining: Int, usdValue: Double)
}

struct ProviderSnapshot: Equatable, Sendable {
    let provider: ProviderID
    let planName: String?
    let windows: [QuotaWindow]
    let billingUsage: BillingUsage?
    /// A short explanation shown under the quotas, such as a shared pool.
    let note: String?
    let fetchedAt: Date

    init(
        provider: ProviderID,
        planName: String?,
        windows: [QuotaWindow],
        billingUsage: BillingUsage? = nil,
        note: String? = nil,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.planName = planName
        self.windows = windows
        self.billingUsage = billingUsage
        self.note = note
        self.fetchedAt = fetchedAt
    }

    var sessionWindow: QuotaWindow? {
        windows.first { $0.kind == .session }
    }

    func window(for metric: MenuBarMetricID) -> QuotaWindow? {
        guard let quotaKind = metric.quotaKind else { return nil }
        return windows.first { $0.kind == quotaKind }
    }

    var availableMenuBarItems: [MenuBarItemID] {
        var items = windows.map {
            MenuBarItemID(provider: provider, metric: $0.kind.menuBarMetric)
        }
        if let billingUsage {
            items.append(MenuBarItemID(
                provider: provider,
                metric: billingUsage.menuBarMetric
            ))
        }
        var seen: Set<MenuBarItemID> = []
        return items.filter { seen.insert($0).inserted }
    }

    func menuBarValue(
        for metric: MenuBarMetricID,
        displayMode: UsageDisplayMode
    ) -> MenuBarReadingValue? {
        if let window = window(for: metric) {
            return .percentage(
                displayMode.displayedPercent(from: window.usedPercent)
            )
        }
        guard billingUsage?.menuBarMetric == metric else { return nil }
        return billingUsage?.menuBarValue(displayMode: displayMode)
    }

    func primaryWindow(for selection: MenuBarWindow) -> QuotaWindow? {
        switch selection {
        case .session:
            windows.first { $0.kind == .session }
        case .weekly:
            windows.first { $0.kind == .weekly }
        }
    }

    func primaryWindowWithFallback(
        for selection: MenuBarWindow
    ) -> QuotaWindow? {
        if let selected = primaryWindow(for: selection) {
            return selected
        }
        let fallback: MenuBarWindow =
            selection == .session ? .weekly : .session
        return primaryWindow(for: fallback)
    }
}

enum ProviderFailureKind: String, Sendable {
    case keychainPermission
    case authentication
    case transient
    case rateLimited
    case invalidResponse
    case storage
}

struct ProviderFailure: LocalizedError, Equatable, Sendable {
    let kind: ProviderFailureKind
    let message: String
    let retryAt: Date?

    /// Messages are user-facing, so literals passed here are extracted into
    /// the String Catalog and shown in the user's language.
    init(_ kind: ProviderFailureKind, _ message: LocalizedStringResource, retryAt: Date? = nil) {
        self.init(kind, verbatim: String(localized: message), retryAt: retryAt)
    }

    init(_ kind: ProviderFailureKind, verbatim message: String, retryAt: Date? = nil) {
        self.kind = kind
        self.message = message
        self.retryAt = retryAt
    }

    var errorDescription: String? { message }

    var preservesLastGood: Bool {
        switch kind {
        case .transient, .rateLimited, .invalidResponse:
            true
        case .authentication, .storage, .keychainPermission:
            false
        }
    }
}

struct ProviderState: Equatable, Sendable {
    let provider: ProviderID
    var snapshot: ProviderSnapshot?
    var failure: ProviderFailure?
    var isRefreshing = false
    var isToolInstalled: Bool?

    var isStale: Bool { snapshot != nil && failure != nil }

    var isVisibleInDashboard: Bool {
        isToolInstalled != false
    }
}

enum MenuBarSelection: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case all
    case claude
    case codex

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: String(localized: "Auto — Highest usage")
        case .all: String(localized: "All providers")
        case .claude: String(localized: "Claude Code")
        case .codex: String(localized: "Codex")
        }
    }

    var provider: ProviderID? {
        switch self {
        case .automatic, .all: nil
        case .claude: .claude
        case .codex: .codex
        }
    }
}

enum MenuBarWindow: String, CaseIterable, Identifiable, Sendable {
    case session
    case weekly

    var id: Self { self }

    var title: String {
        switch self {
        case .session: String(localized: "Session")
        case .weekly: String(localized: "Weekly")
        }
    }
}

enum UsageDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case remaining
    case used

    static let defaultSelection: Self = .remaining

    var id: Self { self }

    var title: String {
        switch self {
        case .used: String(localized: "Used")
        case .remaining: String(localized: "Left")
        }
    }

    var valueSuffix: String {
        switch self {
        case .used: String(localized: "used")
        case .remaining: String(localized: "left")
        }
    }

    func displayedPercent(from usedPercent: Double) -> Double {
        switch self {
        case .used:
            usedPercent
        case .remaining:
            100 - min(max(usedPercent, 0), 100)
        }
    }

    func renderedFraction(from usedPercent: Double) -> Double {
        min(max(displayedPercent(from: usedPercent) / 100, 0), 1)
    }
}

enum RefreshIntervalOption: String, CaseIterable, Identifiable, Sendable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour

    var id: Self { self }

    var title: String {
        switch self {
        case .oneMinute: String(localized: "Every minute")
        case .fiveMinutes: String(localized: "Every 5 minutes")
        case .fifteenMinutes: String(localized: "Every 15 minutes")
        case .thirtyMinutes: String(localized: "Every 30 minutes")
        case .oneHour: String(localized: "Every hour")
        }
    }

    var duration: Duration {
        switch self {
        case .oneMinute: .seconds(60)
        case .fiveMinutes: .seconds(300)
        case .fifteenMinutes: .seconds(900)
        case .thirtyMinutes: .seconds(1_800)
        case .oneHour: .seconds(3_600)
        }
    }
}

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async throws -> ProviderSnapshot
    func authorizeKeychainAccess() async throws
}

extension UsageProvider {
    func authorizeKeychainAccess() async throws {}
}

/// The weekly allowance of The X Subscription, which Grok and Cursor share.
struct XSubscriptionPool: Equatable, Sendable {
    let tierName: String
    let usedPercent: Double
    let resetsAt: Date?

    /// Shown as the plan badge, for example "X Plus".
    var planName: String { "X \(tierName)" }
}

protocol XSubscriptionPoolReading: Sendable {
    func fetchXSubscriptionPool() async -> XSubscriptionPool?
}

protocol DateProviding: Sendable {
    func now() -> Date
}

struct SystemDateProvider: DateProviding {
    func now() -> Date { Date() }
}

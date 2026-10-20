import AppKit
import SwiftUI

struct DashboardView: View {
    @Bindable var store: UsageStore
    @Bindable var launchAtLogin: LaunchAtLoginController
    @Binding var usageDisplayMode: UsageDisplayMode
    @Binding var refreshInterval: RefreshIntervalOption
    let availableUpdateVersion: String?
    let isCheckingForUpdates: Bool
    var checkForUpdates: @MainActor () -> Void = {}
    var openSettings: @MainActor () -> Void = {}

    var body: some View {
        // Keep the container on the footer only. One spanning the scroll view
        // lets the provider cards' glass escape the scroll clip and draw over
        // the header and footer.
        DashboardContentView(
            store: store,
            usageDisplayMode: $usageDisplayMode
        )
        .safeAreaBar(edge: .bottom, spacing: 0) {
            GlassEffectContainer(spacing: 10) {
                footer
            }
        }
        .frame(width: 392)
        .onAppear {
            store.setRefreshInterval(refreshInterval)
            store.start()
            launchAtLogin.synchronize()
        }
        .onChange(of: refreshInterval) { _, interval in
            store.setRefreshInterval(interval)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: freshnessSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(freshnessTint)

                Group {
                    if let updated = store.lastSuccessfulRefreshAt {
                        // Minute precision. A per-second relative date keeps
                        // redrawing while the closed panel waits for reuse.
                        TimelineView(.everyMinute) { context in
                            Text(Self.updatedText(updated, now: context.date))
                        }
                    } else if store.lastAttemptAt != nil {
                        Text("Not updated")
                    } else {
                        Text("Waiting to refresh")
                    }
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer()

            if let version = availableUpdateVersion {
                Button(action: checkForUpdates) {
                    Label("Update", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(UsagePalette.accent)
                .controlSize(.small)
                .disabled(isCheckingForUpdates)
                .help("Update AI Usage Plus to \(version)")
            }

            HStack(spacing: 0) {
                Button {
                    store.refreshNow()
                } label: {
                    RefreshButtonLabel(isRefreshing: isRefreshing)
                }
                .help(isRefreshing ? "Refreshing usage" : "Refresh now")
                .disabled(isRefreshing)

                Button(action: openSettings) {
                    SettingsButtonLabel()
                }
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityHint("Shows settings in the menu bar panel")
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 7)
    }

    static func updatedText(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "Updated just now") }
        let elapsed = date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        return String(localized: "Updated \(elapsed)")
    }

    private var freshnessSymbol: String {
        store.lastSuccessfulRefreshAt == nil ? "clock" : "checkmark.circle.fill"
    }

    private var freshnessTint: Color {
        store.lastSuccessfulRefreshAt == nil ? .secondary : UsagePalette.success
    }

    private var isRefreshing: Bool {
        store.states.values.contains(where: \.isRefreshing)
    }
}

struct SettingsButtonLabel: View {
    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: RefreshButtonLabel.symbolSize, weight: .medium))
            .frame(width: RefreshButtonLabel.size, height: RefreshButtonLabel.size)
            .contentShape(Circle())
    }
}

struct RefreshButtonLabel: View {
    static let size: CGFloat = 28
    static let symbolSize: CGFloat = 14

    let isRefreshing: Bool

    var body: some View {
        ZStack {
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .font(.system(size: Self.symbolSize, weight: .medium))
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .accessibilityLabel(isRefreshing ? "Refreshing usage" : "Refresh now")
    }
}

struct DashboardContentView: View {
    @Bindable var store: UsageStore
    @Binding var usageDisplayMode: UsageDisplayMode

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 10)
            providerRows
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var providerRows: some View {
        if visibleProviders.count > 2 {
            // Span the panel's full width and pad inside the scroll view, so
            // its clip never cuts through the cards' glass shadows and leaves
            // a hard-edged dark band beside them.
            ScrollView {
                providerRowsContent
                    .padding(Self.rowsInsets)
            }
            .frame(maxHeight: 390)
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        } else {
            providerRowsContent
                .padding(Self.rowsInsets)
        }
    }

    private static let rowsInsets = EdgeInsets(top: 8, leading: 10, bottom: 6, trailing: 10)

    private var providerRowsContent: some View {
        LazyVStack(spacing: 8) {
            ForEach(visibleProviders) { provider in
                if let state = store.states[provider] {
                    ProviderSectionView(
                        state: state,
                        displayMode: usageDisplayMode,
                        authorizeKeychain: {
                            Task { await store.authorizeKeychainAccess(for: provider) }
                        }
                    )
                }
            }
        }
    }

    private var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter(store.isProviderVisibleInDashboard)
    }

    private var header: some View {
        HStack {
            Text("AI Usage Plus")
                .font(.headline.weight(.semibold))
            Spacer()
            Picker("Numbers", selection: $usageDisplayMode) {
                ForEach(UsageDisplayMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 112)
            .accessibilityLabel("Usage numbers")
            .accessibilityHint("Choose whether percentages show usage left or used")
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
    }
}

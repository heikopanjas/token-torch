import AppKit
import BurnCore
import SwiftUI

@main
struct BurnApp: App {
    @State private var model = MenuBarViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
                .frame(width: 360)
        } label: {
            MenuBarStatusIcon()
        }
        .menuBarExtraStyle(.window)

        Window("burn Settings", id: "settings") {
            SettingsTabView()
                .frame(minWidth: 520, minHeight: 420)
                .onDisappear {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppActions.requestOpenSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit") {
                    AppActions.quit()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}

private enum AppActions {
    static let openSettingsNotification = Notification.Name("burn.openSettings")
    static let burnRefreshRequested = Notification.Name("burn.refreshRequested")

    static func requestOpenSettings() {
        NotificationCenter.default.post(name: openSettingsNotification, object: nil)
    }

    static func openSettings(openWindow: OpenWindowAction) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }

    static func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
@Observable
final class MenuBarViewModel {
    var result: AllProvidersResult?
    var isLoading = false
    private let orchestrator = UsageOrchestrator(credentialStrategy: .burnOwnedCopy)
    private var timer: Timer?

    init() {
        NotificationCenter.default.addObserver(
            forName: AppActions.burnRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        scheduleRefresh()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let fetched = await orchestrator.fetchAll()
            await MainActor.run {
                self.result = fetched
                self.isLoading = false
            }
        }
    }

    private func scheduleRefresh() {
        refresh()
        let minutes = ProviderPreferencesStore.shared.load().refreshIntervalMinutes
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}

struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if let result = model.result {
                    Text("Updated \(result.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(height: 16, alignment: .center)

            Divider()

            if let result = model.result {
                ForEach(Array(result.results.enumerated()), id: \.element.provider) { index, providerResult in
                    if index > 0 {
                        Divider()
                    }
                    ProviderSectionView(result: providerResult)
                }
            }
            else {
                Text("No enabled providers. Open Settings.")
                    .foregroundStyle(.secondary)
            }

            Divider()
            VStack(spacing: 0) {
                MenuBarCommandRow(
                    title: "Refresh",
                    shortcutLabel: "⌘R",
                    key: "r",
                    modifiers: .command,
                    isDisabled: model.isLoading,
                    action: { model.refresh() }
                )
                MenuBarCommandRow(
                    title: "Settings…",
                    shortcutLabel: "⌘,",
                    key: ",",
                    modifiers: .command,
                    action: { AppActions.openSettings(openWindow: openWindow) }
                )
                MenuBarCommandRow(
                    title: "Quit",
                    shortcutLabel: "⌘Q",
                    key: "q",
                    modifiers: .command,
                    action: AppActions.quit
                )
            }
        }
        .padding(12)
        .onReceive(NotificationCenter.default.publisher(for: AppActions.openSettingsNotification)) { _ in
            AppActions.openSettings(openWindow: openWindow)
        }
    }
}

private struct MenuBarCommandRow: View {
    let title: String
    let shortcutLabel: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 16)
                Text(shortcutLabel)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: modifiers)
        .disabled(isDisabled)
    }
}

struct ProviderSectionView: View {
    let result: ProviderFetchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(result.reports.enumerated()), id: \.offset) { index, report in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 4)
                }
                ProviderReportView(provider: result.provider, report: report)
            }
        }
        .padding(.top, 4)
    }
}

private struct ProviderReportView: View {
    let provider: ProviderID
    let report: ProviderReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ProviderIconView(provider: provider, report: report)
                Text(reportHeading)
                    .font(.subheadline.bold())
                Spacer(minLength: 8)
                if case .subscription(let quota) = report, provider == .cursor, let summary = Self.cursorPlanSummary(quota) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            switch report {
                case .subscription(let quota):
                    if quota.provider == "Cursor" {
                        if let start = quota.billingCycleStart, let end = quota.billingCycleEnd {
                            Text("Billing cycle: \(MenuFormat.billingCycleDate(start)) → \(MenuFormat.billingCycleDate(end))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer().frame(height: 8)
                        CursorUsagePercentLines(quota: quota)
                        if let total = Self.cursorGrandTotalLabel(quota) {
                            Spacer().frame(height: 8)
                            HStack {
                                Text("Grand Total:")
                                Spacer(minLength: 8)
                                Text(total)
                                    .monospacedDigit()
                            }
                            .font(.subheadline.bold())
                        }
                    }
                    else {
                        SubscriptionMenuView(quota: quota)
                    }
                case .org(let org):
                    OrgBillingMenuView(org: org)
                case .error(_, let mode, let message):
                    Text("\(mode): \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
            }
        }
    }

    private static func cursorPlanSummary(_ quota: SubscriptionQuotaReport) -> String? {
        switch (quota.planTier, quota.planPrice) {
            case (.some(let tier), .some(let price)): "\(tier) · \(price)"
            case (.some(let tier), .none): tier
            case (.none, .some(let price)): price
            case (.none, .none): nil
        }
    }

    private static func cursorGrandTotalLabel(_ quota: SubscriptionQuotaReport) -> String? {
        if let api = quota.apiAllowance {
            let used = QuotaHelpers.centsToDollars(api.usedCents)
            let limit = QuotaHelpers.centsToDollars(api.limitCents)
            return String(format: "$%.2f/$%.2f", used, limit)
        }
        if let usage = quota.dollarUsage {
            let used = QuotaHelpers.centsToDollars(usage.usedCents)
            let limit = QuotaHelpers.centsToDollars(usage.limitCents)
            return String(format: "$%.2f/$%.2f", used, limit)
        }
        return nil
    }

    private var reportHeading: String {
        switch provider {
            case .codex:
                switch report {
                    case .subscription: "ChatGPT & Codex"
                    case .org: "OpenAI Platform"
                    case .error(_, let mode, _): mode == "subscription" ? "ChatGPT & Codex" : "OpenAI Platform"
                }
            case .claude:
                switch report {
                    case .subscription: "Claude & Claude Code"
                    case .org: "Anthropic API"
                    case .error(_, let mode, _): mode == "subscription" ? "Claude & Claude Code" : "Anthropic API"
                }
            case .cursor:
                switch report {
                    case .subscription: "Cursor Plan"
                    case .org: provider.displayName
                    case .error(_, let mode, _): mode == "subscription" ? "Cursor Plan" : provider.displayName
                }
        }
    }
}

private enum MenuBarIcon {
    private static let side: CGFloat = 18

    static func image() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "cursor", withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: side, height: side)
        image.isTemplate = false
        return image
    }
}

private struct MenuBarStatusIcon: View {
    var body: some View {
        Group {
            if let image = MenuBarIcon.image() {
                Image(nsImage: image)
            }
            else {
                Image(systemName: "flame.fill")
            }
        }
        .accessibilityLabel("burn")
    }
}

private enum ProviderIcons {
    static func resourceName(for provider: ProviderID, report: ProviderReport) -> String {
        switch provider {
            case .claude:
                switch report {
                    case .subscription: "claude"
                    case .org: "anthropic"
                    case .error(_, let mode, _): mode == "subscription" ? "claude" : "anthropic"
                }
            case .codex: "openai"
            case .cursor: "cursor"
        }
    }

    static func image(for provider: ProviderID, report: ProviderReport) -> NSImage? {
        let name = resourceName(for: provider, report: report)
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = false
        return image
    }
}

private struct ProviderIconView: View {
    let provider: ProviderID
    let report: ProviderReport

    var body: some View {
        Group {
            if let image = ProviderIcons.image(for: provider, report: report) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }
}

private struct SubscriptionMenuView: View {
    let quota: SubscriptionQuotaReport

    var body: some View {
        ForEach(quota.windows) { window in
            QuotaWindowRow(window: window)
        }
    }
}

private struct OrgBillingMenuView: View {
    let org: OrgUsageReport

    private var sortedCostRows: [OrgCostRow] {
        org.costRows.sorted { $0.costUSD > $1.costUSD }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(billingCycleLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 8)

            if sortedCostRows.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            else {
                ForEach(sortedCostRows, id: \.label) { row in
                    HStack {
                        Text(row.label)
                        Spacer(minLength: 8)
                        Text(MenuFormat.orgCostUSD(row.costUSD))
                            .monospacedDigit()
                    }
                    .font(.subheadline.bold())
                }

                Spacer().frame(height: 8)

                HStack {
                    Text("Grand Total:")
                    Spacer(minLength: 8)
                    Text(MenuFormat.orgCostUSD(org.grandTotalUSD))
                        .monospacedDigit()
                }
                .font(.subheadline.bold())
            }
        }
    }

    private var billingCycleLine: String {
        if let end = org.endDate {
            return "Billing cycle: \(org.startDate) → \(end)"
        }
        return "Billing cycle: \(org.startDate)"
    }

    private var emptyMessage: String {
        org.provider == "OpenAI" ? "No billed costs in this period." : "No billable usage in this period."
    }
}

private struct CursorUsagePercentLines: View {
    private static let meterLabels = [
        "Included total usage",
        "Auto + Composer",
        "Included API usage"
    ]

    let quota: SubscriptionQuotaReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Self.meterLabels, id: \.self) { label in
                if let window = quota.windows.first(where: { $0.label == label }) {
                    HStack {
                        Text(label)
                        Spacer(minLength: 8)
                        Text(String(format: "%.0f%% used", window.usedPercent))
                            .monospacedDigit()
                    }
                    .font(.subheadline.bold())
                }
            }
        }
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    var showReset: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(String(format: "%.0f%% used", window.usedPercent))
                    .foregroundStyle(MenuFormat.percentColor(window.usedPercent))
                    .monospacedDigit()
            }
            if showReset, let resetsAt = window.resetsAt {
                Text("resets \(MenuFormat.resetTime(resetsAt))")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
        }
    }
}

private enum MenuFormat {
    static func billingCycleDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    static func resetTime(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: value) + " UTC"
    }

    static func percentColor(_ usedPercent: Double) -> Color {
        if usedPercent >= 80 { return .red }
        if usedPercent >= 50 { return .yellow }
        return .green
    }

    static func orgCostUSD(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }
}

struct SettingsTabView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProviderSettingsTab(provider: .claude)
                .tabItem { Label("Claude", systemImage: "sparkles") }
            ProviderSettingsTab(provider: .codex)
                .tabItem { Label("Codex", systemImage: "bubble.left.and.bubble.right") }
            ProviderSettingsTab(provider: .cursor)
                .tabItem { Label("Cursor", systemImage: "cursorarrow.rays") }
        }
        .padding(16)
    }
}

struct GeneralSettingsTab: View {
    @State private var refreshMinutes = ProviderPreferencesStore.shared.load().refreshIntervalMinutes

    var body: some View {
        Form {
            Stepper("Refresh every \(refreshMinutes) minutes", value: $refreshMinutes, in: 5 ... 120, step: 5)
                .onChange(of: refreshMinutes) { _, newValue in
                    var prefs = ProviderPreferencesStore.shared.load()
                    prefs.refreshIntervalMinutes = newValue
                    ProviderPreferencesStore.shared.save(prefs)
                }
            Text(
                "Subscription quotas import vendor OAuth into burn’s Keychain once (a login prompt is OK the first time). Routine refresh reads only burn’s copy. Admin keys below are stored in burn’s Keychain."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct ProviderSettingsTab: View {
    let provider: ProviderID
    @State private var flags: ProviderModeFlags
    @State private var adminKey = ""
    @State private var status = ""

    private let keychain = AppKeychainStore.shared
    private let preferences = ProviderPreferencesStore.shared

    init(provider: ProviderID) {
        self.provider = provider
        let prefs = ProviderPreferencesStore.shared.load()
        _flags = State(initialValue: prefs.flags(for: provider))
    }

    var body: some View {
        Form {
            Toggle("Enable subscription quota", isOn: $flags.subscriptionQuotaEnabled)
                .onChange(of: flags) { _, newValue in saveFlags(newValue) }

            Text(
                "Clears burn’s copied subscription credentials only. Vendor app logins are not changed. Use after re-login in Claude Code, Codex CLI, or Cursor IDE."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("Reset subscription credentials") {
                resetSubscriptionCredentials()
            }

            if provider.supportsOrgBilling {
                Toggle("Enable API billing", isOn: $flags.orgBillingEnabled)
                    .onChange(of: flags) { _, newValue in saveFlags(newValue) }
            }

            if provider.supportsOrgBilling {
                SecureField("Admin key", text: $adminKey)
                HStack {
                    Button("Save key") { saveKey() }
                    Button("Clear key", role: .destructive) { clearKey() }
                }
            }

            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadKeys() }
    }

    private func saveFlags(_ newFlags: ProviderModeFlags) {
        var prefs = preferences.load()
        prefs.setFlags(newFlags, for: provider)
        preferences.save(prefs)
    }

    private func loadKeys() {
        adminKey = (try? keychain.load(provider: provider, kind: .adminKey)) ?? ""
    }

    private func saveKey() {
        do {
            if adminKey.isEmpty {
                try keychain.delete(provider: provider, kind: .adminKey)
            }
            else {
                try keychain.save(provider: provider, kind: .adminKey, value: adminKey)
            }
            status = "Saved."
        }
        catch {
            status = Redaction.redactSecrets(error.localizedDescription)
        }
    }

    private func clearKey() {
        try? keychain.delete(provider: provider, kind: .adminKey)
        adminKey = ""
        status = "Key cleared."
    }

    private func resetSubscriptionCredentials() {
        do {
            if flags.subscriptionQuotaEnabled {
                try VendorCredentialImporter.resetAndReimport(
                    provider: provider,
                    quotaEnabled: flags.subscriptionQuotaEnabled
                )
                status = "Credentials reset and re-imported."
            }
            else {
                try VendorCredentialImporter.reset(provider: provider)
                status = "Stored credentials cleared."
            }
            NotificationCenter.default.post(name: AppActions.burnRefreshRequested, object: nil)
        }
        catch {
            status = Redaction.redactSecrets(error.localizedDescription)
        }
    }
}

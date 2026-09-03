import Foundation

@MainActor
@Observable
final class MenuBarViewModel {
    var result: AllProvidersResult?
    var isLoading = false
    var onUpdated: (() -> Void)?

    private let orchestrator = UsageOrchestrator()
    private var timer: Timer?
    private var pendingNonInteractiveRefresh = false
    private var isWaitingForNetwork = false
    private var lastRepairFailureNotified = false

    init() {
        NotificationCenter.default.addObserver(
            forName: AppActions.tokenTorchRefreshRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(interactive: true)
            }
        }
        NotificationCenter.default.addObserver(
            forName: .networkStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.networkStatusChanged()
            }
        }
        scheduleRefresh()
    }

    func refresh(interactive: Bool = false) {
        guard interactive == true else {
            refreshWhenNetworkReady()
            return
        }

        pendingNonInteractiveRefresh = false
        performRefresh(interactive: true)
    }

    func rescheduleTimer() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshWhenNetworkReady()
        let minutes = ProviderPreferencesStore.shared.load().refreshIntervalMinutes
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshWhenNetworkReady() }
        }
    }

    private func refreshWhenNetworkReady() {
        guard isLoading == false else { return }
        pendingNonInteractiveRefresh = true
        startPendingRefreshWait(timeoutSeconds: 60)
    }

    private func startPendingRefreshWait(timeoutSeconds: Double) {
        guard isWaitingForNetwork == false else { return }
        isWaitingForNetwork = true

        Task { [weak self] in
            await NetworkManager.shared.startMonitoring()
            let isReady = await NetworkManager.shared.waitForConnection(timeoutSeconds: timeoutSeconds)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWaitingForNetwork = false
                guard isReady == true else { return }
                self.runPendingNonInteractiveRefresh()
            }
        }
    }

    private func networkStatusChanged() {
        guard pendingNonInteractiveRefresh, isLoading == false else { return }
        startPendingRefreshWait(timeoutSeconds: 15)
    }

    private func runPendingNonInteractiveRefresh() {
        guard pendingNonInteractiveRefresh, isLoading == false else { return }
        pendingNonInteractiveRefresh = false
        performRefresh(interactive: false)
    }

    private func performRefresh(interactive: Bool) {
        guard isLoading == false else { return }
        isLoading = true
        notifyUpdated()
        Task {
            let fetched = await orchestrator.fetchAll(interactive: interactive)
            let prefs = ProviderPreferencesStore.shared.load()
            MenuTrackingRefresh.perform {
                self.result = fetched
                self.isLoading = false
                if interactive == false {
                    let failureMessage = fetched.claudeRepairFailureMessage
                    if let failureMessage,
                        self.lastRepairFailureNotified == false,
                        prefs.notifyOnRepairFailure
                    {
                        NotificationService.post(.claudeRepairFailed(message: failureMessage))
                    }
                    self.lastRepairFailureNotified = (failureMessage != nil)
                }
                self.evaluateUsageAlerts(fetched, preferences: prefs)
                self.notifyUpdated()
            }
        }
    }

    /// Runs on every refresh, interactive or not: this is a persisted state machine, not a one-shot
    /// notice, so an interactive refresh that first observes a new band must still record it — else
    /// the next timer tick would banner a crossing the user already saw on screen. State is saved
    /// unconditionally so enabling the toggle mid-band doesn't immediately burst a backlog.
    private func evaluateUsageAlerts(_ result: AllProvidersResult, preferences: ProviderPreferences) {
        let rows = CappedUsageRows.rows(in: result, preferences: preferences)
        let reportingSections = CappedUsageRows.reportingSections(in: result, preferences: preferences)
        let outcome = UsageAlertEvaluator.evaluate(
            rows: rows,
            previous: UsageAlertStateStore.shared.load(),
            startLevel: preferences.usageAlertStartLevel,
            reportingSections: reportingSections
        )
        UsageAlertStateStore.shared.save(outcome.state)
        guard preferences.notifyOnUsageThreshold == true else { return }
        for (section, alerts) in Dictionary(grouping: outcome.alerts, by: \.key.section) {
            NotificationService.post(.usageThresholdReached(section: section, rows: alerts))
        }
    }

    private func notifyUpdated() {
        onUpdated?()
    }
}

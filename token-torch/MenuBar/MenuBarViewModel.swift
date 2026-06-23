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
        guard interactive else {
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
        guard !isLoading else { return }
        pendingNonInteractiveRefresh = true
        startPendingRefreshWait(timeoutSeconds: 60)
    }

    private func startPendingRefreshWait(timeoutSeconds: Double) {
        guard !isWaitingForNetwork else { return }
        isWaitingForNetwork = true

        Task { [weak self] in
            await NetworkManager.shared.startMonitoring()
            let isReady = await NetworkManager.shared.waitForConnection(timeoutSeconds: timeoutSeconds)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isWaitingForNetwork = false
                guard isReady else { return }
                self.runPendingNonInteractiveRefresh()
            }
        }
    }

    private func networkStatusChanged() {
        guard pendingNonInteractiveRefresh, !isLoading else { return }
        startPendingRefreshWait(timeoutSeconds: 15)
    }

    private func runPendingNonInteractiveRefresh() {
        guard pendingNonInteractiveRefresh, !isLoading else { return }
        pendingNonInteractiveRefresh = false
        performRefresh(interactive: false)
    }

    private func performRefresh(interactive: Bool) {
        guard !isLoading else { return }
        isLoading = true
        notifyUpdated()
        Task {
            let fetched = await orchestrator.fetchAll(interactive: interactive)
            MenuTrackingRefresh.perform {
                self.result = fetched
                self.isLoading = false
                self.notifyUpdated()
            }
        }
    }

    private func notifyUpdated() {
        onUpdated?()
    }
}

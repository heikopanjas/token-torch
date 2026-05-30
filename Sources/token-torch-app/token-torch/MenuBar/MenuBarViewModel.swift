import TokenTorchCore
import Foundation

@MainActor
@Observable
final class MenuBarViewModel {
    var result: AllProvidersResult?
    var isLoading = false
    var onUpdated: (() -> Void)?

    private let orchestrator = UsageOrchestrator(credentialStrategy: .tokenTorchOwnedCopy)
    private var timer: Timer?

    init() {
        NotificationCenter.default.addObserver(
            forName: AppActions.tokenTorchRefreshRequested,
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
        notifyUpdated()
        Task {
            let fetched = await orchestrator.fetchAll()
            await MainActor.run {
                self.result = fetched
                self.isLoading = false
                self.notifyUpdated()
            }
        }
    }

    func rescheduleTimer() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refresh()
        let minutes = ProviderPreferencesStore.shared.load().refreshIntervalMinutes
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func notifyUpdated() {
        onUpdated?()
    }
}

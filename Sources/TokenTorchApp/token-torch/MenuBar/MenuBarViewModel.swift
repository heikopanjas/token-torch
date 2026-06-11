import Foundation
import TokenTorchCore

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
            Task { @MainActor in
                self?.refresh(interactive: true)
            }
        }
        scheduleRefresh()
    }

    func refresh(interactive: Bool = false) {
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

    func rescheduleTimer() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refresh(interactive: false)
        let minutes = ProviderPreferencesStore.shared.load().refreshIntervalMinutes
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(interactive: false) }
        }
    }

    private func notifyUpdated() {
        onUpdated?()
    }
}

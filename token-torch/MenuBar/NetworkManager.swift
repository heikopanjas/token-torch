import Foundation
import Network

actor NetworkManager {
    static let shared = NetworkManager()

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "TokenTorchNetworkMonitor")
    private(set) var isConnected = false
    private(set) var connectionType: ConnectionType = .unknown
    private var isMonitoringStarted = false
    private var initialConnectionCheckCompleted = false

    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
    }

    private init() {}

    func startMonitoring() async {
        guard isMonitoringStarted == false else { return }

        setupMonitor()
        monitor.start(queue: monitorQueue)
        isMonitoringStarted = true
        await waitForInitialConnectionCheck()
    }

    func waitForConnection(timeoutSeconds: Double) async -> Bool {
        if isConnected == true {
            return await checkActualConnectivity()
        }

        return await withCheckedContinuation { continuation in
            let connectionMonitor = NWPathMonitor()
            let monitorQueue = DispatchQueue(label: "TokenTorchConnectionWaitMonitor")
            let connectionWaiter = ConnectionWaiter()

            connectionMonitor.pathUpdateHandler = { path in
                guard path.status == .satisfied else { return }

                Task {
                    let didComplete = await connectionWaiter.tryComplete()
                    guard didComplete == true else { return }

                    connectionMonitor.cancel()
                    let hasConnectivity = await self.checkActualConnectivity()
                    continuation.resume(returning: hasConnectivity)
                }
            }

            connectionMonitor.start(queue: monitorQueue)

            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                let didComplete = await connectionWaiter.tryComplete()
                guard didComplete == true else { return }

                connectionMonitor.cancel()
                continuation.resume(returning: false)
            }
        }
    }

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            Task {
                await self.updateConnectionStatus(path: path)
            }
        }
    }

    private func waitForInitialConnectionCheck() async {
        let deadline = Date().addingTimeInterval(5)
        while initialConnectionCheckCompleted == false && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }

        if initialConnectionCheckCompleted == false {
            initialConnectionCheckCompleted = true
        }
    }

    private func updateConnectionStatus(path: NWPath) {
        let wasConnected = isConnected
        isConnected = path.status == .satisfied
        updateConnectionType(path)

        if initialConnectionCheckCompleted == false {
            initialConnectionCheckCompleted = true
        }

        guard wasConnected != isConnected else { return }

        Task { @MainActor in
            NotificationCenter.default.post(name: .networkStatusChanged, object: nil)
        }
    }

    private func updateConnectionType(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        }
        else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        }
        else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        }
        else {
            connectionType = .unknown
        }
    }

    private func checkActualConnectivity() async -> Bool {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200 ... 299).contains(httpResponse.statusCode)
        }
        catch {
            return false
        }
    }
}

private actor ConnectionWaiter {
    private var isCompleted = false

    func tryComplete() -> Bool {
        guard isCompleted == false else { return false }

        isCompleted = true
        return true
    }
}

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("tokenTorch.networkStatusChanged")
}

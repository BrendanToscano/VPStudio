import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected: Bool = true
    private(set) var isExpensive: Bool = false
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "com.vpstudio.network-monitor")
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }
}

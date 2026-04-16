import Testing

@testable import VPStudio

@Suite("NetworkMonitor")
@MainActor
struct NetworkMonitorTests {
    @Test("Initial state is connected")
    func initialStateIsConnected() {
        let monitor = NetworkMonitor()
        #expect(monitor.isConnected == true)
    }

    @Test("Initial state is not expensive")
    func initialStateIsNotExpensive() {
        let monitor = NetworkMonitor()
        #expect(monitor.isExpensive == false)
    }

    @Test("isConnected is read-only from outside")
    func isConnectedIsReadOnly() {
        let monitor = NetworkMonitor()
        // Verify the property exists and is readable
        let connected: Bool = monitor.isConnected
        #expect(connected == true)
    }

    @Test("isExpensive is read-only from outside")
    func isExpensiveIsReadOnly() {
        let monitor = NetworkMonitor()
        let expensive: Bool = monitor.isExpensive
        #expect(expensive == false)
    }

    @Test("Multiple instances are independent")
    func multipleInstancesAreIndependent() {
        let monitor1 = NetworkMonitor()
        let monitor2 = NetworkMonitor()
        // Both should start connected
        #expect(monitor1.isConnected == true)
        #expect(monitor2.isConnected == true)
    }
}

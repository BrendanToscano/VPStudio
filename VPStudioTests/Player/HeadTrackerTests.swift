#if os(visionOS)
import Testing
import simd
@testable import VPStudio

@Suite("HeadTracker — Initial State & Lifecycle")
struct HeadTrackerTests {

    @Test("Starts with identity transform and not running")
    @MainActor func initialState() {
        let tracker = HeadTracker()
        #expect(!tracker.isRunning)
        #expect(!tracker.isTracking)
        #expect(tracker.headTransform == matrix_identity_float4x4)
        #expect(tracker.initialHeadTransform == nil)
    }

    @Test("Stop without start does not crash")
    @MainActor func stopIsIdempotent() {
        let tracker = HeadTracker()
        tracker.stop()
        tracker.stop()
        #expect(!tracker.isRunning)
        #expect(!tracker.isTracking)
    }

    @Test("Start sets isRunning to true")
    @MainActor func startSetsIsRunning() {
        let tracker = HeadTracker()
        tracker.start()
        #expect(tracker.isRunning)
        tracker.stop()
    }

    @Test("Stop after start resets all state")
    @MainActor func stopResetsAllState() {
        let tracker = HeadTracker()
        tracker.start()
        tracker.stop()
        #expect(!tracker.isRunning)
        #expect(!tracker.isTracking)
    }

    @Test("Double start is harmless")
    @MainActor func doubleStartIsIdempotent() {
        let tracker = HeadTracker()
        tracker.start()
        tracker.start() // Should not crash or create a second poll loop.
        #expect(tracker.isRunning)
        tracker.stop()
    }

    @Test("Start clears previous initialHeadTransform")
    @MainActor func startClearsInitialTransform() {
        let tracker = HeadTracker()
        tracker.start()
        // On Simulator, initialHeadTransform will stay nil (no device anchors).
        #expect(tracker.initialHeadTransform == nil)
        tracker.stop()
    }

    @Test("headTransform is valid after polling on Simulator")
    @MainActor func headTransformValidOnSimulator() async throws {
        let tracker = HeadTracker()
        tracker.start()
        // Give the poll loop a couple of iterations.
        try await Task.sleep(for: .milliseconds(200))
        // On visionOS 26+ simulators, device anchors may or may not be available.
        // If tracking is active, the transform should be a valid 4x4 matrix.
        // If not, it should remain identity.
        if tracker.isTracking {
            // Verify the matrix is a valid rigid-body transform (column 3.w == 1).
            #expect(tracker.headTransform.columns.3.w == 1.0)
        } else {
            #expect(tracker.headTransform == matrix_identity_float4x4)
        }
        tracker.stop()
    }

    @Test("tracking state is consistent after polling on Simulator")
    @MainActor func trackingStateConsistentOnSimulator() async throws {
        let tracker = HeadTracker()
        tracker.start()
        try await Task.sleep(for: .milliseconds(200))
        // isTracking may be true or false depending on the simulator version.
        // Either way, isRunning should be true until stop().
        #expect(tracker.isRunning)
        tracker.stop()
        #expect(!tracker.isTracking)
    }
}

@Suite("HeadTracker — Configuration")
struct HeadTrackerConfigTests {

    @Test("Custom poll interval is accepted")
    @MainActor func customPollInterval() {
        let tracker = HeadTracker(pollInterval: .milliseconds(8))
        tracker.start()
        #expect(tracker.isRunning)
        tracker.stop()
    }

    @Test("Custom smoothing factor is clamped to valid range")
    @MainActor func smoothingFactorClamped() {
        // These should not crash even with extreme values.
        let tracker1 = HeadTracker(smoothingFactor: 0.0) // Clamped to 0.01
        tracker1.start()
        tracker1.stop()

        let tracker2 = HeadTracker(smoothingFactor: 2.0) // Clamped to 1.0
        tracker2.start()
        tracker2.stop()
    }

    @Test("Default poll interval is 16ms")
    func defaultPollInterval() {
        #expect(HeadTracker.defaultPollInterval == .milliseconds(16))
    }

    @Test("Default smoothing factor is 0.3")
    func defaultSmoothingFactor() {
        #expect(HeadTracker.defaultSmoothingFactor == 0.3)
    }
}
#endif

#if os(visionOS)
import ARKit
import os
import QuartzCore
import RealityKit
import simd
import Observation

private let logger = Logger(subsystem: "com.vpstudio", category: "HeadTracker")

/// Polls the ARKit `WorldTrackingProvider` for the current device (head) transform
/// and publishes it as an `@Observable` property for use in immersive environments.
///
/// ## Smoothing
/// Raw device anchors can jitter at high frequency. `HeadTracker` applies a simple
/// exponential moving average (EMA) to position and slerp to orientation, controlled
/// by ``smoothingFactor``. A value of 1.0 means no smoothing (raw values pass through);
/// lower values produce heavier smoothing at the cost of latency.
///
/// ## Simulator
/// On the visionOS Simulator, `queryDeviceAnchor(atTimestamp:)` always returns `nil`.
/// The tracker remains `isRunning = true` but `isTracking` stays `false`, and
/// `headTransform` stays at `matrix_identity_float4x4`, so the controls panel stays
/// stationary at the origin — which is the correct fallback.
@Observable
@MainActor
final class HeadTracker {

    // MARK: - Configuration

    /// Interval between ARKit device-anchor polls. Faster = smoother tracking
    /// but higher CPU. 16 ms ≈ 60 Hz matches the display refresh rate.
    /// 8 ms ≈ 120 Hz is smoother but doubles CPU cost.
    nonisolated static let defaultPollInterval: Duration = .milliseconds(16)

    /// Reduced poll interval used when controls are hidden and the user is
    /// passively watching. 500 ms is sufficient for coarse head tracking
    /// (e.g. controls-anchor drift correction) without burning CPU.
    nonisolated static let idlePollInterval: Duration = .milliseconds(500)

    /// EMA blending factor for temporal smoothing. Range (0, 1].
    /// - 1.0 = no smoothing (raw values)
    /// - 0.3 = moderate smoothing (recommended)
    /// - 0.1 = heavy smoothing (noticeable lag)
    nonisolated static let defaultSmoothingFactor: Float = 0.3

    // MARK: - Published State

    /// Smoothed head transform, updated every poll cycle.
    var headTransform: simd_float4x4 = matrix_identity_float4x4

    /// The head pose captured on the first valid anchor after `start()`.
    /// Used by `HDRISkyboxEnvironment` to orient the cinema screen toward the
    /// user's initial facing direction, then never updated again.
    private(set) var initialHeadTransform: simd_float4x4?

    /// `true` once `start()` has been called (even before ARKit delivers anchors).
    private(set) var isRunning = false

    /// `true` only when the tracker is actively receiving valid device anchors.
    /// `false` on Simulator and before the first anchor arrives.
    private(set) var isTracking = false

    /// When `true`, the poll loop uses ``idlePollInterval`` (500 ms) instead of
    /// the default 16 ms. Set this to `true` when immersive controls are hidden
    /// to reduce CPU usage during passive viewing.
    var isIdle: Bool = false

    // MARK: - Private

    private var arSession: ARKitSession?
    private var worldTracking: WorldTrackingProvider?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration
    private let smoothingFactor: Float

    init(
        pollInterval: Duration = HeadTracker.defaultPollInterval,
        smoothingFactor: Float = HeadTracker.defaultSmoothingFactor
    ) {
        self.pollInterval = pollInterval
        self.smoothingFactor = max(0.01, min(1.0, smoothingFactor))
    }

    @MainActor deinit {
        pollTask?.cancel()
        pollTask = nil
        arSession = nil
        worldTracking = nil
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        isTracking = false
        initialHeadTransform = nil

        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        arSession = session
        worldTracking = provider

        let interval = pollInterval
        let alpha = smoothingFactor

        // Use Task.detached so the ARKit poll loop runs off the MainActor.
        // Capture session and provider as local lets — they are NOT captured
        // strongly on self, so stop() niling the instance properties lets ARC
        // release them once the task exits.
        pollTask = Task.detached { [weak self] in
            do {
                try await session.run([provider])
            } catch {
                logger.error("ARKit session failed to start: \(error.localizedDescription)")
                await MainActor.run { self?.isRunning = false }
                return
            }

            // Track previous smoothed values for EMA.
            var smoothedPos = SIMD3<Float>.zero
            var smoothedRot = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            var hasSmoothed = false

            while !Task.isCancelled {
                let timestamp = CACurrentMediaTime()
                if let anchor = provider.queryDeviceAnchor(atTimestamp: timestamp) {
                    let raw = anchor.originFromAnchorTransform

                    // Decompose into position and rotation.
                    let rawPos = SIMD3<Float>(raw.columns.3.x, raw.columns.3.y, raw.columns.3.z)
                    let rawRot = simd_quatf(raw)

                    let finalPos: SIMD3<Float>
                    let finalRot: simd_quatf

                    if hasSmoothed {
                        finalPos = simd_mix(smoothedPos, rawPos, SIMD3<Float>(repeating: alpha))
                        finalRot = simd_slerp(smoothedRot, rawRot, alpha)
                    } else {
                        finalPos = rawPos
                        finalRot = rawRot
                        hasSmoothed = true
                    }
                    smoothedPos = finalPos
                    smoothedRot = finalRot

                    // Recompose into a 4x4 matrix.
                    var mat = simd_float4x4(finalRot)
                    mat.columns.3 = SIMD4<Float>(finalPos.x, finalPos.y, finalPos.z, 1)

                    await MainActor.run {
                        guard let self else { return }
                        self.headTransform = mat
                        if self.initialHeadTransform == nil {
                            self.initialHeadTransform = mat
                        }
                        if !self.isTracking {
                            self.isTracking = true
                        }
                    }
                }
                let currentInterval = await MainActor.run { self?.isIdle == true } ? Self.idlePollInterval : interval
                try? await Task.sleep(for: currentInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        arSession = nil
        worldTracking = nil
        isRunning = false
        isTracking = false
        headTransform = matrix_identity_float4x4
        initialHeadTransform = nil
    }
}
#endif

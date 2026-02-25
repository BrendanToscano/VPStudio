import simd

/// Pure-logic policy constants and helpers for immersive cinema controls positioning.
///
/// Extracted from `HDRISkyboxEnvironment` so that smoothing, offsets, and timing
/// values are testable without RealityKit or ARKit dependencies.
enum ImmersiveControlsPolicy {

    /// EMA blending factor for controls anchor tracking. Higher values make the
    /// controls panel respond faster to head movement but may appear jittery;
    /// lower values feel smoother but introduce latency.
    ///
    /// Previous hardcoded value was 0.08, which felt laggy. 0.18 gives a good
    /// balance between responsiveness and smoothness.
    static let controlsAnchorSmoothing: Float = 0.18

    /// How far in front of the user the controls panel is positioned (meters).
    static let controlsForwardOffset: Float = 1.5

    /// Vertical offset from the user's eye line for the controls panel (meters).
    /// Negative = below eye level.
    static let controlsVerticalOffset: Float = -0.15

    /// Duration before immersive controls automatically hide after the last
    /// user interaction.
    static let autoDismissInterval: Duration = .seconds(10)

    /// Controls position used when head tracking is unavailable (e.g. Simulator).
    /// Centered at roughly eye-height and forward of origin.
    static let fallbackControlsPosition = SIMD3<Float>(0, 1.3, -1.5)

    /// Default screen height when no head tracking data is available (meters).
    /// Approximates seated eye level for Apple Vision Pro.
    static let fallbackEyeHeight: Float = 1.6

    /// Applies exponential moving average smoothing between the current position
    /// and a target position using ``controlsAnchorSmoothing`` as the blend factor.
    ///
    /// When `current == target` the result equals both (no drift).
    static func smoothedPosition(current: SIMD3<Float>, target: SIMD3<Float>) -> SIMD3<Float> {
        let t = controlsAnchorSmoothing
        return current + (target - current) * t
    }
}

#if os(visionOS)
import SwiftUI
import Observation
import AVFoundation
import simd

/// Serializable proxy for ImmersionStyle because it is not Equatable/Codable.
public enum CinemaImmersionStyle: String, Codable, Hashable, CaseIterable, Sendable {
    case mixed
    case full
    case progressive
}

/// Preset configurations for the cinema environment.
public enum CinemaPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case `default`, frontRow, backRow, imax, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .default: return "Default"
        case .frontRow: return "Front Row"
        case .backRow: return "Back Row"
        case .imax: return "IMAX"
        case .custom: return "Custom"
        }
    }
}

/// The single source of truth for cinema environment configuration.
/// Uses `@Observable` for fine-grained SwiftUI observation and persists to `UserDefaults`.
@Observable
@MainActor
public final class CinemaSettings {
    @ObservationIgnored private var persistsChanges = true

    // MARK: Screen Geometry (in meters / degrees)
    public var screenWidth: Double       { didSet { persistIfNeeded() } }
    public var screenDistance: Double    { didSet { persistIfNeeded() } }
    public var screenHeight: Double      { didSet { persistIfNeeded() } }
    public var screenTilt: Double        { didSet { persistIfNeeded() } }
    public var seatOffset: SIMD3<Double> { didSet { persistIfNeeded() } }

    // MARK: Environment
    public var environmentDarkness: Double  { didSet { persistIfNeeded() } }  // 0.0...1.0
    public var ambientLighting: Double      { didSet { persistIfNeeded() } }  // 0.0...1.0

    // MARK: Immersion
    public var immersionStyleRaw: String    { didSet { persistIfNeeded() } }  // CinemaImmersionStyle.rawValue
    public var useSurroundingsEffect: Bool  { didSet { persistIfNeeded() } }

    // MARK: Content
    public var videoAspectRatio: Double     { didSet { persistIfNeeded() } }

    // MARK: Derived
    public var screenSize: CGSize {
        CGSize(width: screenWidth, height: screenWidth / videoAspectRatio)
    }
    public var immersionStyle: CinemaImmersionStyle {
        get { CinemaImmersionStyle(rawValue: immersionStyleRaw) ?? .full }
        set { immersionStyleRaw = newValue.rawValue }
    }

    // MARK: Validation / Comfort
    /// Horizontal field of view in degrees subtended by the screen.
    public var horizontalFOV: Double {
        2 * atan((screenWidth / 2) / max(screenDistance, 0.1)) * (180.0 / .pi)
    }
    /// Whether the current configuration exceeds comfortable viewing limits (>60° FOV or <1.5m distance with width >2m).
    public var isComfortable: Bool {
        horizontalFOV <= 60 && (screenDistance >= 1.5 || screenWidth <= 2.0)
    }

    // MARK: Preset
    public func apply(preset: CinemaPreset, baseAspectRatio: Double? = nil) {
        let ratio = baseAspectRatio ?? videoAspectRatio
        switch preset {
        case .default:
            screenWidth = 6.0; screenDistance = 4.0; screenHeight = 0.0; screenTilt = 0.0
            seatOffset = .zero; environmentDarkness = 0.8; ambientLighting = 0.1
            immersionStyleRaw = CinemaImmersionStyle.full.rawValue; useSurroundingsEffect = true
        case .frontRow:
            screenWidth = 5.0; screenDistance = 2.5; screenHeight = -0.3; screenTilt = 5.0
            seatOffset = .zero; environmentDarkness = 1.0; ambientLighting = 0.05
            immersionStyleRaw = CinemaImmersionStyle.full.rawValue; useSurroundingsEffect = true
        case .backRow:
            screenWidth = 4.5; screenDistance = 8.0; screenHeight = 0.5; screenTilt = -3.0
            seatOffset = .zero; environmentDarkness = 0.6; ambientLighting = 0.2
            immersionStyleRaw = CinemaImmersionStyle.progressive.rawValue; useSurroundingsEffect = false
        case .imax:
            screenWidth = 10.0; screenDistance = 3.5; screenHeight = 1.0; screenTilt = 8.0
            seatOffset = [0, 0.1, 0]; environmentDarkness = 1.0; ambientLighting = 0.0
            immersionStyleRaw = CinemaImmersionStyle.full.rawValue; useSurroundingsEffect = true
        case .custom:
            break // no-op
        }
        videoAspectRatio = ratio
    }
    public var activePreset: CinemaPreset {
        get {
            let presets: [CinemaPreset] = [.default, .frontRow, .backRow, .imax]
            for p in presets {
                let s = CinemaSettings(preset: p, baseAspectRatio: videoAspectRatio)
                let match = abs(s.screenWidth - screenWidth) < 0.15
                    && abs(s.screenDistance - screenDistance) < 0.15
                    && abs(s.screenHeight - screenHeight) < 0.15
                    && abs(s.screenTilt - screenTilt) < 1.5
                    && s.immersionStyleRaw == immersionStyleRaw
                    && abs(s.environmentDarkness - environmentDarkness) < 0.05
                    && abs(s.ambientLighting - ambientLighting) < 0.05
                if match { return p }
            }
            return .custom
        }
        set {
            apply(preset: newValue, baseAspectRatio: videoAspectRatio)
        }
    }

    // MARK: Persistence Keys
    private enum Key {
        static let prefix = "CinemaEnvironment."
        static let screenWidth = prefix + "screenWidth"
        static let screenDistance = prefix + "screenDistance"
        static let screenHeight = prefix + "screenHeight"
        static let screenTilt = prefix + "screenTilt"
        static let seatOffsetX = prefix + "seatOffsetX"
        static let seatOffsetY = prefix + "seatOffsetY"
        static let seatOffsetZ = prefix + "seatOffsetZ"
        static let environmentDarkness = prefix + "environmentDarkness"
        static let ambientLighting = prefix + "ambientLighting"
        static let immersionStyle = prefix + "immersionStyle"
        static let useSurroundingsEffect = prefix + "useSurroundingsEffect"
        static let videoAspectRatio = prefix + "videoAspectRatio"
    }

    // MARK: Init
    public init(
        screenWidth: Double = 6.0,
        screenDistance: Double = 4.0,
        screenHeight: Double = 0.0,
        screenTilt: Double = 0.0,
        seatOffset: SIMD3<Double> = .zero,
        environmentDarkness: Double = 0.8,
        ambientLighting: Double = 0.1,
        immersionStyle: CinemaImmersionStyle = .full,
        useSurroundingsEffect: Bool = true,
        videoAspectRatio: Double = 16.0 / 9.0,
        loadPersisted: Bool = true
    ) {
        self.screenWidth = screenWidth
        self.screenDistance = screenDistance
        self.screenHeight = screenHeight
        self.screenTilt = screenTilt
        self.seatOffset = seatOffset
        self.environmentDarkness = environmentDarkness
        self.ambientLighting = ambientLighting
        self.immersionStyleRaw = immersionStyle.rawValue
        self.useSurroundingsEffect = useSurroundingsEffect
        self.videoAspectRatio = videoAspectRatio
        if loadPersisted {
            withPersistenceDisabled {
                load()
            }
        }
    }

    /// Convenience init from preset (does NOT auto-save).
    public convenience init(preset: CinemaPreset, baseAspectRatio: Double = 16.0 / 9.0) {
        self.init(loadPersisted: false)
        withPersistenceDisabled {
            apply(preset: preset, baseAspectRatio: baseAspectRatio)
        }
    }

    // MARK: Persistence
    public func load() {
        let defs = UserDefaults.standard
        screenWidth = defs.object(forKey: Key.screenWidth) as? Double ?? screenWidth
        screenDistance = defs.object(forKey: Key.screenDistance) as? Double ?? screenDistance
        screenHeight = defs.object(forKey: Key.screenHeight) as? Double ?? screenHeight
        screenTilt = defs.object(forKey: Key.screenTilt) as? Double ?? screenTilt
        let sx = defs.object(forKey: Key.seatOffsetX) as? Double ?? seatOffset.x
        let sy = defs.object(forKey: Key.seatOffsetY) as? Double ?? seatOffset.y
        let sz = defs.object(forKey: Key.seatOffsetZ) as? Double ?? seatOffset.z
        seatOffset = SIMD3(sx, sy, sz)
        environmentDarkness = defs.object(forKey: Key.environmentDarkness) as? Double ?? environmentDarkness
        ambientLighting = defs.object(forKey: Key.ambientLighting) as? Double ?? ambientLighting
        immersionStyleRaw = defs.string(forKey: Key.immersionStyle) ?? immersionStyleRaw
        useSurroundingsEffect = defs.object(forKey: Key.useSurroundingsEffect) as? Bool ?? useSurroundingsEffect
        videoAspectRatio = defs.object(forKey: Key.videoAspectRatio) as? Double ?? videoAspectRatio
    }

    public func save() {
        let defs = UserDefaults.standard
        defs.set(screenWidth, forKey: Key.screenWidth)
        defs.set(screenDistance, forKey: Key.screenDistance)
        defs.set(screenHeight, forKey: Key.screenHeight)
        defs.set(screenTilt, forKey: Key.screenTilt)
        defs.set(seatOffset.x, forKey: Key.seatOffsetX)
        defs.set(seatOffset.y, forKey: Key.seatOffsetY)
        defs.set(seatOffset.z, forKey: Key.seatOffsetZ)
        defs.set(environmentDarkness, forKey: Key.environmentDarkness)
        defs.set(ambientLighting, forKey: Key.ambientLighting)
        defs.set(immersionStyleRaw, forKey: Key.immersionStyle)
        defs.set(useSurroundingsEffect, forKey: Key.useSurroundingsEffect)
        defs.set(videoAspectRatio, forKey: Key.videoAspectRatio)
    }

    private func persistIfNeeded() {
        guard persistsChanges else { return }
        save()
    }

    private func withPersistenceDisabled(_ body: () -> Void) {
        let previous = persistsChanges
        persistsChanges = false
        body()
        persistsChanges = previous
    }
}
#endif

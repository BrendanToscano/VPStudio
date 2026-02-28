import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Diagnostics Events

enum RuntimeDiagnosticsEvent: String, Sendable {
    case appBootstrapCompleted = "app_bootstrap_completed"
    case tabSelectionChanged = "tab_selection_changed"
    case libraryLoadStarted = "library_load_started"
    case libraryLoadFinished = "library_load_finished"
    case playerPrepareStarted = "player_prepare_started"
    case playerPrepareSucceeded = "player_prepare_succeeded"
    case playerPrepareFailed = "player_prepare_failed"
    case playerCloseRequested = "player_close_requested"
    case playerDidDisappear = "player_did_disappear"
    case memoryPressureWarning = "memory_pressure_warning"
    case memoryLeakDetected = "memory_leak_detected"
}

// MARK: - Memory Snapshot

struct RuntimeMemorySnapshot: Sendable, Equatable {
    let residentBytes: UInt64
    let timestamp: Date

    var residentMegabytes: Double {
        Double(residentBytes) / 1_048_576.0
    }

    init(residentBytes: UInt64, timestamp: Date = .now) {
        self.residentBytes = residentBytes
        self.timestamp = timestamp
    }
}

// MARK: - Memory Leak Detection

/// Tracks memory snapshots over time to detect potential leaks.
/// A leak is suspected if memory grows consistently without releasing.
struct MemoryLeakDetector: Sendable {
    private var snapshots: [RuntimeMemorySnapshot] = []
    private let maxSnapshots: Int
    private let leakThresholdMB: Double
    private let growthRateThreshold: Double

    init(
        maxSnapshots: Int = 10,
        leakThresholdMB: Double = 100.0,
        growthRateThreshold: Double = 0.15
    ) {
        self.maxSnapshots = maxSnapshots
        self.leakThresholdMB = leakThresholdMB
        self.growthRateThreshold = growthRateThreshold
    }

    /// Records a new snapshot and returns whether a leak is suspected.
    mutating func record(_ snapshot: RuntimeMemorySnapshot) -> Bool {
        snapshots.append(snapshot)

        // Keep only recent snapshots
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }

        return detectLeak()
    }

    /// Detects if memory is consistently growing (potential leak).
    private func detectLeak() -> Bool {
        guard snapshots.count >= 3 else { return false }

        let recent = snapshots.suffix(3)
        guard let first = recent.first, let last = recent.last else { return false }

        let growthMB = last.residentMegabytes - first.residentMegabytes

        // If memory grew by more than threshold and total is above leak threshold
        if growthMB > (first.residentMegabytes * growthRateThreshold) &&
            last.residentMegabytes > leakThresholdMB {
            return true
        }

        return false
    }

    /// Resets the detector state.
    mutating func reset() {
        snapshots.removeAll()
    }
}

// MARK: - Policy

enum RuntimeDiagnosticsPolicy {
    static let maxContextLength = 120

    /// Memory threshold in MB above which leak detection becomes active.
    static let leakDetectionThresholdMB: Double = 150.0

    /// Minimum time interval between snapshots to avoid noise (seconds).
    static let snapshotIntervalSeconds: Double = 2.0

    static func normalizedContext(_ raw: String?) -> String {
        guard let raw else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard trimmed.count > maxContextLength else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxContextLength)
        return "\(trimmed[..<end])..."
    }

    /// Checks if we should take a snapshot based on time interval.
    static func shouldSnapshot(lastSnapshotTime: Date?) -> Bool {
        guard let last = lastSnapshotTime else { return true }
        return Date().timeIntervalSince(last) >= snapshotIntervalSeconds
    }
}

// MARK: - Runtime Memory Diagnostics

enum RuntimeMemoryDiagnostics {
    private static let logger = Logger(subsystem: "com.vpstudio.app", category: "runtime-diagnostics")
    private static var leakDetector = MemoryLeakDetector()
    private static var lastSnapshotTime: Date?

    /// Captures a diagnostic event with optional memory snapshot.
    /// When leak detection is enabled, also tracks memory over time.
    static func capture(
        event: RuntimeDiagnosticsEvent,
        enabled: Bool,
        context: String? = nil
    ) {
        guard enabled else { return }

        let normalizedContext = RuntimeDiagnosticsPolicy.normalizedContext(context)
        guard let snapshot = currentSnapshot() else {
            if normalizedContext.isEmpty {
                logger.log("[\(event.rawValue, privacy: .public)] rss=unavailable")
            } else {
                logger.log("[\(event.rawValue, privacy: .public)] rss=unavailable context=\(normalizedContext, privacy: .public)")
            }
            return
        }

        // Check for potential leaks periodically
        if RuntimeDiagnosticsPolicy.shouldSnapshot(lastSnapshotTime: lastSnapshotTime) {
            let leakDetected = leakDetector.record(snapshot)
            lastSnapshotTime = snapshot.timestamp

            if leakDetected {
                logger.warning("Potential memory leak detected! RSS: \(String(format: "%.2f", snapshot.residentMegabytes))MB")
                leakDetector.reset()
            }
        }

        let message = formattedMessage(event: event, snapshot: snapshot, context: normalizedContext)
        logger.log("\(message, privacy: .public)")
    }

    /// Formats a diagnostic message for logging.
    static func formattedMessage(
        event: RuntimeDiagnosticsEvent,
        snapshot: RuntimeMemorySnapshot,
        context: String
    ) -> String {
        if context.isEmpty {
            return "[\(event.rawValue)] rss=\(String(format: "%.2f", snapshot.residentMegabytes))MB"
        }
        return "[\(event.rawValue)] rss=\(String(format: "%.2f", snapshot.residentMegabytes))MB context=\(context)"
    }

    /// Gets the current memory snapshot.
    static func currentSnapshot() -> RuntimeMemorySnapshot? {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }

        guard status == KERN_SUCCESS else { return nil }
        return RuntimeMemorySnapshot(residentBytes: UInt64(info.resident_size))
        #else
        return nil
        #endif
    }

    /// Resets the leak detector state. Useful for testing.
    static func resetLeakDetector() {
        leakDetector.reset()
        lastSnapshotTime = nil
    }
}

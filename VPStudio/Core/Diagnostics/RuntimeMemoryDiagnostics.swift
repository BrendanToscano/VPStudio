import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

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
}

struct RuntimeMemorySnapshot: Sendable, Equatable {
    let residentBytes: UInt64

    var residentMegabytes: Double {
        Double(residentBytes) / 1_048_576.0
    }
}

enum RuntimeDiagnosticsPolicy {
    static let maxContextLength = 120

    static func normalizedContext(_ raw: String?) -> String {
        guard let raw else { return "" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard trimmed.count > maxContextLength else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxContextLength)
        return "\(trimmed[..<end])..."
    }
}

enum RuntimeMemoryDiagnostics {
    private static let logger = Logger(subsystem: "com.vpstudio.app", category: "runtime-diagnostics")

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

        let message = formattedMessage(event: event, snapshot: snapshot, context: normalizedContext)
        logger.log("\(message, privacy: .public)")
    }

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
}

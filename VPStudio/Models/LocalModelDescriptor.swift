import Foundation
import GRDB

// MARK: - Status

enum LocalModelStatus: String, Codable, Sendable, Equatable {
    case available
    case downloading
    case paused
    case downloaded
    case corrupted
    case failed
}

enum LocalModelValidation: String, Codable, Sendable, Equatable {
    case pending
    case valid
    case corrupt
}

// MARK: - Descriptor

struct LocalModelDescriptor: Codable, Sendable, Identifiable, Equatable,
                              FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_models"

    // Core identity
    var id: String                          // e.g. "mlx-community/Qwen3.5-4B-4bit"
    var displayName: String                 // e.g. "Qwen 3.5 4B"
    var huggingFaceRepo: String             // HuggingFace repo identifier
    var revision: String                    // commit hash for pinned version
    var parameterCount: String              // "4B", "3B", "3.8B"
    var quantization: String                // "4bit", "8bit"

    // Size
    var diskSizeMB: Int                     // Expected total download size
    var minMemoryMB: Int                    // Minimum RAM to load model
    var expectedFileCount: Int              // Number of files in the repo

    // Context — device-aware caps computed at seed time
    var maxContextTokens: Int               // Native model context window
    var effectivePromptCap: Int             // Device-aware prompt token limit
    var effectiveOutputCap: Int             // Device-aware output token limit

    // Status & progress
    var status: LocalModelStatus
    var downloadProgress: Double            // 0.0...1.0
    var downloadedBytes: Int64              // Bytes downloaded so far
    var totalBytes: Int64                   // Total expected bytes
    var lastProgressAt: Date?               // For stall detection

    // Integrity
    var checksumSHA256: String?             // Expected checksum (nil if not available)
    var validationState: LocalModelValidation

    // Storage
    var localPath: String?                  // Full path on disk once downloaded
    var partialDownloadPath: String?        // Path for in-progress download
    var isDefault: Bool

    // Timestamps
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - State Machine

extension LocalModelDescriptor {

    /// Legal status transitions
    static func canTransition(from: LocalModelStatus, to: LocalModelStatus) -> Bool {
        switch (from, to) {
        case (.available, .downloading),
             (.downloading, .downloaded),
             (.downloading, .paused),
             (.downloading, .failed),
             (.paused, .downloading),
             (.failed, .downloading),
             (.downloaded, .corrupted),
             (.corrupted, .available):
            return true
        default:
            return false
        }
    }

    /// Delete resets any state back to available
    mutating func resetToAvailable() {
        status = .available
        downloadProgress = 0
        downloadedBytes = 0
        lastProgressAt = nil
        localPath = nil
        partialDownloadPath = nil
        validationState = .pending
        updatedAt = Date()
    }
}

// MARK: - Device Caps

extension LocalModelDescriptor {

    /// Compute effective caps based on device class
    static func effectiveCaps(
        nativeContext: Int,
        isVisionPro: Bool
    ) -> (promptCap: Int, outputCap: Int) {
        if isVisionPro {
            // Vision Pro: 16GB shared with spatial rendering — conservative
            return (min(nativeContext, 8192), 2048)
        } else {
            // Mac: more headroom — use up to half native context
            return (min(nativeContext, 32768), 4096)
        }
    }
}

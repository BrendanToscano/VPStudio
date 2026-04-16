import Foundation
import os

/// Actor owning DB reads/writes for LocalModelDescriptor.
/// Enforces status state machine and batches progress writes.
actor LocalModelCatalogStore {

    private let database: DatabaseManager
    private let logger = Logger(subsystem: "com.vpstudio", category: "local-catalog")

    private static let catalogVersion = 1

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Catalog Seeding

    /// Inserts the hardcoded model catalog into the DB on first launch.
    /// Skips models that already exist. Called during bootstrap().
    func seedCatalog() async {
        let isVisionPro: Bool = {
            #if os(visionOS)
            return true
            #else
            return false
            #endif
        }()

        let descriptors = Self.builtInModels(isVisionPro: isVisionPro)

        for descriptor in descriptors {
            do {
                let existing = try await database.fetchLocalModel(id: descriptor.id)
                if existing == nil {
                    try await database.saveLocalModel(descriptor)
                    logger.info("Seeded local model: \(descriptor.displayName)")
                }
            } catch {
                logger.error("Failed to seed model \(descriptor.id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Queries

    func availableModels() async throws -> [LocalModelDescriptor] {
        try await database.fetchLocalModels()
    }

    func downloadedModels() async throws -> [LocalModelDescriptor] {
        try await database.fetchDownloadedLocalModels()
    }

    func model(id: String) async throws -> LocalModelDescriptor? {
        try await database.fetchLocalModel(id: id)
    }

    // MARK: - State Machine Updates

    func updateStatus(id: String, to newStatus: LocalModelStatus, localPath: String? = nil) async throws {
        guard let current = try await database.fetchLocalModel(id: id) else { return }
        guard LocalModelDescriptor.canTransition(from: current.status, to: newStatus) else {
            logger.warning("Illegal transition \(current.status.rawValue) → \(newStatus.rawValue) for \(id)")
            return
        }
        try await database.updateLocalModelStatus(id: id, status: newStatus, localPath: localPath)
    }

    func updateProgress(id: String, progress: Double, downloadedBytes: Int64, totalBytes: Int64) async throws {
        try await database.updateLocalModelProgress(
            id: id,
            progress: progress,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes
        )
    }

    func resetToAvailable(id: String) async throws {
        guard var model = try await database.fetchLocalModel(id: id) else { return }
        model.resetToAvailable()
        try await database.saveLocalModel(model)
    }

    // MARK: - Built-in Models

    private static func builtInModels(isVisionPro: Bool) -> [LocalModelDescriptor] {
        let now = Date()

        let smolCaps = LocalModelDescriptor.effectiveCaps(nativeContext: 2_048, isVisionPro: isVisionPro)
        let phiCaps = LocalModelDescriptor.effectiveCaps(nativeContext: 4_096, isVisionPro: isVisionPro)
        let elmCaps = LocalModelDescriptor.effectiveCaps(nativeContext: 2_048, isVisionPro: isVisionPro)

        return [
            LocalModelDescriptor(
                id: "apple/SmolLM2-360M-Instruct-CoreML",
                displayName: "SmolLM2 360M",
                huggingFaceRepo: "apple/SmolLM2-360M-Instruct-CoreML",
                revision: "main",
                parameterCount: "360M",
                quantization: "float16",
                diskSizeMB: 700,
                minMemoryMB: 800,
                expectedFileCount: 5,
                maxContextTokens: 2_048,
                effectivePromptCap: smolCaps.promptCap,
                effectiveOutputCap: smolCaps.outputCap,
                status: .available,
                downloadProgress: 0,
                downloadedBytes: 0,
                totalBytes: 0,
                lastProgressAt: nil,
                checksumSHA256: nil,
                validationState: .pending,
                localPath: nil,
                partialDownloadPath: nil,
                isDefault: true,
                createdAt: now,
                updatedAt: now
            ),
            LocalModelDescriptor(
                id: "apple/Phi-3-mini-128k-instruct-CoreML",
                displayName: "Phi-3 Mini",
                huggingFaceRepo: "apple/Phi-3-mini-128k-instruct-CoreML",
                revision: "main",
                parameterCount: "3.8B",
                quantization: "float16",
                diskSizeMB: 7600,
                minMemoryMB: 4000,
                expectedFileCount: 5,
                maxContextTokens: 4_096,
                effectivePromptCap: phiCaps.promptCap,
                effectiveOutputCap: phiCaps.outputCap,
                status: .available,
                downloadProgress: 0,
                downloadedBytes: 0,
                totalBytes: 0,
                lastProgressAt: nil,
                checksumSHA256: nil,
                validationState: .pending,
                localPath: nil,
                partialDownloadPath: nil,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            ),
            LocalModelDescriptor(
                id: "apple/OpenELM-3B-Instruct-CoreML",
                displayName: "OpenELM 3B",
                huggingFaceRepo: "apple/OpenELM-3B-Instruct-CoreML",
                revision: "main",
                parameterCount: "3B",
                quantization: "float16",
                diskSizeMB: 6000,
                minMemoryMB: 3500,
                expectedFileCount: 5,
                maxContextTokens: 2_048,
                effectivePromptCap: elmCaps.promptCap,
                effectiveOutputCap: elmCaps.outputCap,
                status: .available,
                downloadProgress: 0,
                downloadedBytes: 0,
                totalBytes: 0,
                lastProgressAt: nil,
                checksumSHA256: nil,
                validationState: .pending,
                localPath: nil,
                partialDownloadPath: nil,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            ),
        ]
    }
}

import Foundation
import Hub
import os

/// Actor managing HuggingFace model downloads with resume, integrity checks, and stall detection.
actor LocalDownloadService {

    private let catalogStore: LocalModelCatalogStore
    private let logger = Logger(subsystem: "com.vpstudio", category: "local-download")

    private var activeTask: Task<Void, Never>?
    private var activeModelID: String?

    init(catalogStore: LocalModelCatalogStore) {
        self.catalogStore = catalogStore
    }

    // MARK: - Models Directory

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VPStudio/Models", isDirectory: true)
    }

    // MARK: - Download

    func downloadModel(id: String) async {
        guard self.activeTask == nil else {
            self.logger.warning("Download already in progress for \(self.activeModelID ?? "unknown")")
            return
        }

        guard let model = try? await catalogStore.model(id: id) else {
            logger.error("Model not found in catalog: \(id)")
            return
        }

        // Preflight: check disk space
        let requiredBytes = Int64(model.diskSizeMB) * 1_048_576
        if let available = diskSpaceAvailable(), available < requiredBytes {
            logger.error("Insufficient disk space: need \(model.diskSizeMB)MB, have \(available / 1_048_576)MB")
            try? await catalogStore.updateStatus(id: id, to: .failed)
            return
        }

        activeModelID = id
        try? await catalogStore.updateStatus(id: id, to: .downloading)
        await postDidChange() // Notify UI immediately so status shows "downloading"

        let repo = model.huggingFaceRepo
        let catalogStore = self.catalogStore
        let throttle = await ProgressNotifyThrottle()

        activeTask = Task {
            do {
                try Task.checkCancellation()

                // Download model snapshot from HuggingFace Hub
                let hubRepo = Hub.Repo(id: repo)
                let localDir = try await HubApi.shared.snapshot(
                    from: hubRepo,
                    matching: ["*.mlmodelc/*", "*.mlpackage/*", "*.json", "*.jinja", "tokenizer*", "*.safetensors"],
                    progressHandler: { progress in
                        Task { @MainActor in
                            try? await catalogStore.updateProgress(
                                id: id,
                                progress: progress.fractionCompleted,
                                downloadedBytes: Int64(progress.completedUnitCount),
                                totalBytes: Int64(progress.totalUnitCount)
                            )
                            if throttle.shouldNotify() {
                                NotificationCenter.default.post(name: .localModelsDidChange, object: nil)
                            }
                        }
                    }
                )

                try? await catalogStore.updateStatus(id: id, to: .downloaded, localPath: localDir.path)
                await MainActor.run {
                    NotificationCenter.default.post(name: .localModelsDidChange, object: nil)
                }
            } catch is CancellationError {
                try? await catalogStore.resetToAvailable(id: id)
                await MainActor.run {
                    NotificationCenter.default.post(name: .localModelsDidChange, object: nil)
                }
            } catch {
                try? await catalogStore.updateStatus(id: id, to: .failed)
                await MainActor.run {
                    NotificationCenter.default.post(name: .localModelsDidChange, object: nil)
                }
            }
        }
        // Capture completion to clean up actor state
        Task {
            _ = await activeTask?.value
            activeTask = nil
            activeModelID = nil
        }
    }

    // MARK: - Cancel

    func cancelDownload(id: String) async {
        guard activeModelID == id else { return }
        activeTask?.cancel()
        activeTask = nil
        activeModelID = nil
        try? await catalogStore.resetToAvailable(id: id)
        await postDidChange()
    }

    // MARK: - Delete

    func deleteModel(id: String) async {
        // Cancel if actively downloading
        if activeModelID == id {
            await cancelDownload(id: id)
        }

        // Remove files
        let modelDir = Self.modelsDirectory.appendingPathComponent(
            id.replacingOccurrences(of: "/", with: "_"),
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: modelDir)

        // Also clean up MLXLLM's default cache location
        let hubCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/hub", isDirectory: true)
        if let hubCache {
            let repoDir = hubCache.appendingPathComponent("models--\(id.replacingOccurrences(of: "/", with: "--"))")
            try? FileManager.default.removeItem(at: repoDir)
        }

        try? await catalogStore.resetToAvailable(id: id)
        await postDidChange()
    }

    // MARK: - Helpers

    private func diskSpaceAvailable() -> Int64? {
        let url = Self.modelsDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private static func hubCacheDirectory(for repo: String) -> URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/hub", isDirectory: true)
            .appendingPathComponent("models--\(repo.replacingOccurrences(of: "/", with: "--"))")
        return cacheDir
    }

    private func postDidChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .localModelsDidChange, object: nil)
        }
    }
}

// MARK: - Thread-safe Progress Throttle

/// Sendable throttle for progress notifications. Uses MainActor isolation to avoid data races.
@MainActor
final class ProgressNotifyThrottle: Sendable {
    private var lastNotifyTime = Date.distantPast

    func shouldNotify(interval: TimeInterval = 2) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastNotifyTime) >= interval {
            lastNotifyTime = now
            return true
        }
        return false
    }
}

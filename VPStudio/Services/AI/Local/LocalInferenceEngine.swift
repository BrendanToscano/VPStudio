import Foundation
import os

/// Actor owning model load/unload/generate lifecycle with memory-aware management.
actor LocalInferenceEngine {

    private let catalogStore: LocalModelCatalogStore
    private let adapter: any LocalInferenceAdapting
    private let logger = Logger(subsystem: "com.vpstudio", category: "local-inference")

    private var loadedModel: LoadedLocalModel?
    private var loadedModelID: String?
    private var lastUsed: Date?
    private var idleUnloadTask: Task<Void, Never>?

    private static let idleTimeout: Duration = .seconds(300)       // 5 minutes
    private static let warmWindow: TimeInterval = 120              // keep warm if used in last 2 min
    private static let generationTimeout: Duration = .seconds(300) // 5 min max per generation (excludes load time)

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var thermalObserver: NSObjectProtocol?

    init(catalogStore: LocalModelCatalogStore, adapter: any LocalInferenceAdapting = CoreMLInferenceAdapter()) {
        self.catalogStore = catalogStore
        self.adapter = adapter
    }

    // MARK: - Memory Pressure Monitoring

    /// Call once after init to start listening for memory/thermal pressure.
    func startMonitoring() {
        // Memory pressure via GCD
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global())
        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.forceUnload() }
        }
        source.resume()
        memoryPressureSource = source

        // Thermal state changes
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                guard let self else { return }
                Task { await self.forceUnload() }
            }
        }

        logger.info("Memory pressure and thermal monitoring started")
    }

    func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
        thermalObserver = nil
    }

    // MARK: - Memory Check

    enum MemoryAvailability: Sendable {
        case ok
        case tight(availableMB: Int, requiredMB: Int)
        case insufficient(availableMB: Int, requiredMB: Int)
    }

    func checkMemory(for modelID: String) async -> MemoryAvailability {
        guard let model = try? await catalogStore.model(id: modelID) else { return .insufficient(availableMB: 0, requiredMB: 0) }
        let availableBytes = os_proc_available_memory()
        let availableMB = Int(availableBytes / 1_048_576)
        let requiredMB = model.minMemoryMB

        if availableMB >= requiredMB * 2 {
            return .ok
        } else if availableMB >= requiredMB {
            return .tight(availableMB: availableMB, requiredMB: requiredMB)
        } else {
            return .insufficient(availableMB: availableMB, requiredMB: requiredMB)
        }
    }

    // MARK: - Load / Unload

    func loadModel(id: String) async throws {
        // Already loaded
        if loadedModelID == id { return }

        // Unload previous
        if loadedModel != nil {
            await unloadModel()
        }

        // Memory preflight — log only, don't block.
        // os_proc_available_memory() on visionOS is conservative because the system
        // holds reclaimable GPU/compositor caches. The OS will reclaim when MLX allocates.
        let memCheck = await checkMemory(for: id)
        switch memCheck {
        case .insufficient(let avail, let req):
            logger.warning("Memory looks tight: \(avail)MB available, \(req)MB preferred — proceeding anyway")
        case .tight(let avail, let req):
            logger.info("Memory adequate but tight: \(avail)MB available, \(req)MB preferred")
        case .ok:
            break
        }

        guard let descriptor = try? await catalogStore.model(id: id),
              descriptor.status == .downloaded else {
            throw LocalInferenceError.modelNotDownloaded
        }

        logger.info("Loading model: \(descriptor.displayName)")
        guard let localPath = descriptor.localPath else {
            throw LocalInferenceError.modelNotDownloaded
        }
        loadedModel = try await adapter.loadModel(from: URL(fileURLWithPath: localPath))
        loadedModelID = id
        lastUsed = Date()
        resetIdleTimer()
        logger.info("Model loaded: \(descriptor.displayName)")
    }

    func unloadModel() async {
        guard loadedModel != nil else { return }
        let name = loadedModelID ?? "unknown"
        loadedModel = nil
        loadedModelID = nil
        lastUsed = nil
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        // CoreML handles its own memory cleanup on model dealloc
        logger.info("Model unloaded: \(name)")
    }

    /// Force unload on memory pressure — no hysteresis check.
    func forceUnload() async {
        await unloadModel()
    }

    // MARK: - Generate

    func generate(
        modelID: String,
        system: String,
        userMessage: String,
        maxTokens: Int = 4096
    ) async throws -> LocalGenerationResult {
        // Load model separately — not subject to generation timeout.
        // First load mmaps weights from disk which can take 30-60s.
        if loadedModelID != modelID {
            logger.info("Model not loaded, loading before generation...")
            try await loadModel(id: modelID)
        }

        guard let model = loadedModel else {
            throw LocalInferenceError.modelNotDownloaded
        }

        let descriptor = try? await catalogStore.model(id: modelID)
        let effectiveMax = min(maxTokens, descriptor?.effectiveOutputCap ?? maxTokens)

        lastUsed = Date()
        logger.info("Starting generation (max \(effectiveMax) tokens)...")

        // Timeout applies only to generation, not model loading
        let result = try await withThrowingTaskGroup(of: LocalGenerationResult.self) { group in
            group.addTask {
                try await self.adapter.generate(
                    model: model,
                    system: system,
                    userMessage: userMessage,
                    maxTokens: effectiveMax
                )
            }

            group.addTask {
                try await Task.sleep(for: Self.generationTimeout)
                throw LocalInferenceError.generationTimeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        logger.info("Generation complete: \(result.outputTokens) tokens")
        resetIdleTimer()
        return result
    }

    // MARK: - Idle Timer

    private func resetIdleTimer() {
        idleUnloadTask?.cancel()
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard let self else { return }
            // Hysteresis: skip unload if recently used
            if let lastUsed = await self.lastUsed,
               Date().timeIntervalSince(lastUsed) < Self.warmWindow {
                await self.resetIdleTimer()
                return
            }
            await self.unloadModel()
        }
    }
}

// MARK: - Errors

enum LocalInferenceError: LocalizedError {
    case modelNotDownloaded
    case insufficientMemory(availableMB: Int, requiredMB: Int)
    case generationTimeout
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "Model not downloaded. Please download it first in Settings → AI."
        case .insufficientMemory(let avail, let req):
            return "Insufficient memory: \(avail)MB available, \(req)MB required."
        case .generationTimeout:
            return "Generation timed out after 2 minutes."
        case .inferenceError(let msg):
            return "Inference error: \(msg)"
        }
    }
}

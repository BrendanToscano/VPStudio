import Foundation

typealias DebridServiceFactory = @Sendable (DebridServiceType, String) -> any DebridServiceProtocol

actor DebridManager {
    private let database: DatabaseManager
    private let secretStore: any SecretStore
    private let serviceFactory: DebridServiceFactory
    private var services: [DebridServiceType: any DebridServiceProtocol] = [:]
    private var servicePriority: [DebridServiceType: Int] = [:]
    private var hasInitialized = false

    init(
        database: DatabaseManager,
        secretStore: any SecretStore,
        serviceFactory: @escaping DebridServiceFactory = DebridManager.liveServiceFactory
    ) {
        self.database = database
        self.secretStore = secretStore
        self.serviceFactory = serviceFactory
    }

    func initialize() async throws {
        var newServices: [DebridServiceType: any DebridServiceProtocol] = [:]
        var newPriority: [DebridServiceType: Int] = [:]

        let configs = try await database.fetchDebridConfigs()
        for config in configs {
            guard let token = try await resolveToken(config.apiTokenRef) else { continue }
            let service = serviceFactory(config.serviceType, token)
            newServices[config.serviceType] = service
            newPriority[config.serviceType] = config.priority
        }

        // Swap atomically after all configs are resolved successfully.
        services = newServices
        servicePriority = newPriority
        hasInitialized = true
    }

    func getService(_ type: DebridServiceType) -> (any DebridServiceProtocol)? {
        services[type]
    }

    func availableServices() -> [DebridServiceType] {
        Array(services.keys).sorted { $0.rawValue < $1.rawValue }
    }

    func checkCacheAcrossServices(hashes: [String]) async throws -> [String: (CacheStatus, DebridServiceType)] {
        try await ensureServicesInitializedIfNeeded()

        // Normalize to lowercase for consistent lookups across services
        let normalizedHashes = hashes.map { $0.lowercased() }
        var results: [String: (CacheStatus, DebridServiceType)] = [:]

        await withTaskGroup(of: (DebridServiceType, [String: CacheStatus]).self) { group in
            for (type, service) in services {
                group.addTask {
                    do {
                        let cache = try await service.checkCache(hashes: normalizedHashes)
                        return (type, cache)
                    } catch {
                        return (type, [:])
                    }
                }
            }

            for await (serviceType, cacheResult) in group {
                for (hash, status) in cacheResult {
                    if case .cached = status {
                        if let existing = results[hash], case .cached = existing.0 {
                            let existingPriority = servicePriority[existing.1] ?? Int.max
                            let newPriority = servicePriority[serviceType] ?? Int.max
                            if newPriority < existingPriority {
                                results[hash] = (status, serviceType)
                            }
                        } else {
                            results[hash] = (status, serviceType)
                        }
                    } else if results[hash] == nil {
                        results[hash] = (status, serviceType)
                    }
                }
            }
        }

        return results
    }

    func resolveStream(hash: String, preferredService: DebridServiceType? = nil) async throws -> StreamInfo {
        try await ensureServicesInitializedIfNeeded()

        let service: any DebridServiceProtocol
        if let preferred = preferredService, let svc = services[preferred] {
            service = svc
        } else if let selectedType = services.keys.min(by: { lhs, rhs in
            let lhsPriority = servicePriority[lhs] ?? .max
            let rhsPriority = servicePriority[rhs] ?? .max
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.rawValue < rhs.rawValue
        }), let selected = services[selectedType] {
            service = selected
        } else {
            throw DebridError.networkError("No debrid services configured. Add one in Settings > Debrid Services.")
        }

        let torrentId = try await service.addMagnet(hash: hash)
        try await service.selectFiles(torrentId: torrentId, fileIds: [])

        // Poll for completion with exponential backoff
        var delay: UInt64 = 500_000_000 // 0.5s
        let maxAttempts = 30
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            do {
                let stream = try await service.getStreamURL(torrentId: torrentId)
                return stream
            } catch DebridError.fileNotReady {
                if attempt < maxAttempts - 1 {
                    try await Task.sleep(nanoseconds: delay)
                    delay = min(delay * 2, 5_000_000_000) // max 5s
                }
            }
        }

        throw DebridError.timeout
    }

    private func resolveToken(_ ref: String) async throws -> String? {
        if let secretKey = SecretReference.decode(ref) {
            return try await secretStore.getSecret(for: secretKey)
        }
        return ref
    }

    private func ensureServicesInitializedIfNeeded() async throws {
        if !hasInitialized {
            try await initialize()
        }
    }

    private static func liveServiceFactory(type: DebridServiceType, token: String) -> any DebridServiceProtocol {
        switch type {
        case .realDebrid:
            return RealDebridService(apiToken: token)
        case .allDebrid:
            return AllDebridService(apiToken: token)
        case .premiumize:
            return PremiumizeService(apiToken: token)
        case .torBox:
            return TorBoxService(apiToken: token)
        case .debridLink:
            return DebridLinkService(apiToken: token)
        case .offcloud:
            return OffcloudService(apiToken: token)
        case .easyNews:
            return EasyNewsService(apiToken: token)
        }
    }
}

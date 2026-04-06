import Foundation

typealias DebridServiceFactory = @Sendable (DebridServiceType, String) -> any DebridServiceProtocol

actor QADebridService: DebridServiceProtocol {
    let serviceType: DebridServiceType

    private let fixture: QADebridFixture
    private var torrentHashesByID: [String: String] = [:]
    private var streamRequestCountsByHash: [String: Int] = [:]

    init(fixture: QADebridFixture) {
        self.serviceType = fixture.serviceType
        self.fixture = fixture
    }

    func validateToken() async throws -> Bool { true }

    func getAccountInfo() async throws -> DebridAccountInfo {
        DebridAccountInfo(username: "qa-fixture", email: nil, premiumExpiry: nil, isPremium: true)
    }

    func checkCache(hashes: [String]) async throws -> [String: CacheStatus] {
        hashes.reduce(into: [String: CacheStatus]()) { result, hash in
            let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedHash == fixture.hash {
                result[normalizedHash] = .cached(fileId: nil, fileName: fixture.fileName, fileSize: nil)
            } else {
                result[normalizedHash] = .notCached
            }
        }
    }

    func addMagnet(hash: String) async throws -> String {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedHash == fixture.hash else {
            throw DebridError.invalidHash(hash)
        }

        let torrentId = "qa-\(normalizedHash)"
        torrentHashesByID[torrentId] = normalizedHash
        return torrentId
    }

    func selectFiles(torrentId: String, fileIds: [Int]) async throws {}

    func getStreamURL(torrentId: String) async throws -> StreamInfo {
        guard let hash = torrentHashesByID[torrentId], hash == fixture.hash else {
            throw DebridError.torrentNotFound(torrentId)
        }

        let requestCount = streamRequestCountsByHash[hash, default: 0]
        streamRequestCountsByHash[hash] = requestCount + 1
        let streamURL = fixture.streamURLs[min(requestCount, fixture.streamURLs.count - 1)]
        let fileName = fixture.fileName

        return StreamInfo(
            streamURL: streamURL,
            quality: VideoQuality.parse(from: fileName),
            codec: VideoCodec.parse(from: fileName),
            audio: AudioFormat.parse(from: fileName),
            source: SourceType.parse(from: fileName),
            hdr: HDRFormat.parse(from: fileName),
            fileName: fileName,
            sizeBytes: nil,
            debridService: serviceType.rawValue
        )
    }

    func unrestrict(link: String) async throws -> URL {
        guard let url = URL(string: link) else {
            throw DebridError.networkError("Invalid QA fixture URL")
        }
        return url
    }
}

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

    func resolveStream(
        hash: String,
        preferredService: DebridServiceType? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) async throws -> StreamInfo {
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
        if let seasonNumber, let episodeNumber {
            var selectedEpisodeFile = false

            if let realDebridService = service as? RealDebridService {
                selectedEpisodeFile = try await realDebridService.selectMatchingEpisodeFile(
                    torrentId: torrentId,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber
                )
            } else if let torBoxService = service as? TorBoxService {
                selectedEpisodeFile = try await torBoxService.selectMatchingEpisodeFile(
                    torrentId: torrentId,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber
                )
            } else if let allDebridService = service as? AllDebridService {
                selectedEpisodeFile = try await allDebridService.selectMatchingEpisodeFile(
                    torrentId: torrentId,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber
                )
            }

            if !selectedEpisodeFile {
                try await service.selectFiles(torrentId: torrentId, fileIds: [])
            }
        } else {
            try await service.selectFiles(torrentId: torrentId, fileIds: [])
        }

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
        if let fixture = QARuntimeOptions.debridFixture,
           fixture.serviceType == type {
            return QADebridService(fixture: fixture)
        }

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

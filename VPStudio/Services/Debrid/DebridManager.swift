import Foundation
import os

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
            let normalizedHash = DebridHashValidator.normalizedInfoHash(hash)
            let lookupKey = normalizedHash ?? hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedHash == fixture.hash {
                result[lookupKey] = .cached(fileId: nil, fileName: fixture.fileName, fileSize: nil)
            } else {
                result[lookupKey] = .notCached
            }
        }
    }

    func addMagnet(hash: String) async throws -> String {
        let normalizedHash = try DebridHashValidator.validatedInfoHash(hash)
        guard normalizedHash == fixture.hash else { throw DebridError.invalidHash(hash) }

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
    private static let logger = Logger(subsystem: "com.vpstudio", category: "debrid-manager")
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
            guard config.supportsSharedMagnetResolveFlow else { continue }
            guard let token = try await resolveToken(for: config) else { continue }
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

        let normalizedHashes = Self.normalizedCacheHashes(hashes)
        let orderedServices = orderedServiceTypes()
        guard !orderedServices.isEmpty else { return [:] }
        let cacheBatchSize = 48

        var results: [String: (CacheStatus, DebridServiceType)] = [:]
        var pendingHashes = Set(normalizedHashes)
        var successfulChecks = 0
        var firstFailure: Error?
        var firstSuccessfulService: DebridServiceType?

        for serviceType in orderedServices {
            guard let service = services[serviceType] else { continue }
            guard !pendingHashes.isEmpty else { break }

            let hashesToCheck = normalizedHashes.filter { pendingHashes.contains($0) }
            for batch in Self.chunked(hashesToCheck, size: cacheBatchSize) {
                do {
                    let cacheResult = try await service.checkCache(hashes: batch)
                    successfulChecks += 1
                    firstSuccessfulService = firstSuccessfulService ?? serviceType

                    for (hash, status) in cacheResult {
                        guard pendingHashes.contains(hash) else { continue }
                        if case .cached = status {
                            results[hash] = (status, serviceType)
                            pendingHashes.remove(hash)
                        }
                    }
                } catch {
                    firstFailure = firstFailure ?? error
                    Self.logger.error("Cache check failed for \(serviceType.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if successfulChecks == 0, let firstFailure {
            throw firstFailure
        }

        let fallbackService = firstSuccessfulService ?? orderedServices.first ?? .realDebrid
        for hash in normalizedHashes where results[hash] == nil {
            let unresolvedStatus: CacheStatus = firstFailure == nil ? .notCached : .unknown
            results[hash] = (unresolvedStatus, fallbackService)
        }

        return results
    }

    func resolveStream(
        hash: String,
        preferredService: DebridServiceType? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) async throws -> StreamInfo {
        return try await resolveStream(
            hash: hash,
            preferredService: preferredService,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            resolvedFileNameHint: nil,
            resolvedFileSizeHint: nil
        )
    }

    func resolveStream(from context: StreamRecoveryContext) async throws -> StreamInfo {
        await cleanupRemoteTransfer(using: context)
        let preferredService = context.resolvedDebridService
            .flatMap(DebridServiceType.init(rawValue:))
            ?? context.preferredService
        return try await resolveStream(
            hash: context.infoHash,
            preferredService: preferredService,
            seasonNumber: context.seasonNumber,
            episodeNumber: context.episodeNumber,
            resolvedFileNameHint: context.resolvedFileName,
            resolvedFileSizeHint: context.resolvedFileSizeBytes
        )
    }

    private func resolveStream(
        hash: String,
        preferredService: DebridServiceType? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) async throws -> StreamInfo {
        try await ensureServicesInitializedIfNeeded()

        let candidateServices = orderedServiceTypes(preferredService: preferredService)
        guard !candidateServices.isEmpty else {
            throw DebridError.networkError("No debrid services configured. Add one in Settings > Debrid Services.")
        }

        var firstFailure: Error?
        for serviceType in candidateServices {
            guard let service = services[serviceType] else { continue }

            do {
                return try await resolveStream(
                    using: service,
                    hash: hash,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    resolvedFileNameHint: resolvedFileNameHint,
                    resolvedFileSizeHint: resolvedFileSizeHint
                )
            } catch {
                if !shouldFailover(from: error) {
                    throw error
                }

                firstFailure = firstFailure ?? error
                Self.logger.error("Stream resolve failed for \(serviceType.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if let firstFailure {
            throw firstFailure
        }

        throw DebridError.networkError("No debrid services configured. Add one in Settings > Debrid Services.")
    }

    private func resolveStream(
        using service: any DebridServiceProtocol,
        hash: String,
        seasonNumber: Int?,
        episodeNumber: Int?,
        resolvedFileNameHint: String?,
        resolvedFileSizeHint: Int64?
    ) async throws -> StreamInfo {
            let torrentId = try await service.addMagnet(hash: hash)
        do {
            if let seasonNumber, let episodeNumber {
                let selectedEpisodeFile = try await service.selectMatchingEpisodeFile(
                    torrentId: torrentId,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                    resolvedFileNameHint: resolvedFileNameHint,
                    resolvedFileSizeHint: resolvedFileSizeHint
                )

                if !selectedEpisodeFile {
                    throw DebridError.networkError("Could not deterministically select the requested episode file.")
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
                    return stream.withRecoveryContext(
                        StreamRecoveryContext(
                            infoHash: hash,
                            preferredService: service.serviceType,
                            seasonNumber: seasonNumber,
                            episodeNumber: episodeNumber,
                            torrentId: torrentId,
                            resolvedDebridService: service.serviceType.rawValue,
                            resolvedFileName: stream.fileName,
                            resolvedFileSizeBytes: stream.sizeBytes
                        )
                    )
                } catch DebridError.fileNotReady {
                    if attempt < maxAttempts - 1 {
                        try await Task.sleep(nanoseconds: delay)
                        delay = min(delay * 2, 5_000_000_000) // max 5s
                    }
                }
            }

            throw DebridError.timeout
        } catch {
            await cleanupRemoteTransfer(
                torrentId: torrentId,
                on: service,
                serviceType: service.serviceType,
                reason: error
            )
            throw error
        }
    }

    func cleanupRemoteTransfer(from context: StreamRecoveryContext) async {
        await cleanupRemoteTransfer(using: context)
    }

    private func resolveToken(for config: DebridConfig) async throws -> String? {
        let storedRef = config.apiTokenRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storedRef.isEmpty else {
            return nil
        }

        if let secretKey = SecretReference.decode(storedRef) {
            return try await secretStore.getSecret(for: secretKey)
        }

        let migratedSecretKey = SecretKey.debridToken(service: config.serviceType, configId: config.id)
        try await secretStore.setSecret(storedRef, for: migratedSecretKey)

        let migratedConfig = DebridConfig(
            id: config.id,
            serviceType: config.serviceType,
            apiTokenRef: SecretReference.encode(key: migratedSecretKey),
            isActive: config.isActive,
            priority: config.priority,
            createdAt: config.createdAt,
            updatedAt: Date()
        )
        try await database.saveDebridConfig(migratedConfig)
        return storedRef
    }

    private func ensureServicesInitializedIfNeeded() async throws {
        if !hasInitialized {
            try await initialize()
        }
    }

    private func cleanupRemoteTransfer(using context: StreamRecoveryContext) async {
        guard let torrentId = context.torrentId else { return }
        let serviceType = context.resolvedDebridService
            .flatMap(DebridServiceType.init(rawValue:))
            ?? context.preferredService
        guard let serviceType else { return }
        guard let service = services[serviceType] else { return }
        await cleanupRemoteTransfer(torrentId: torrentId, on: service, serviceType: serviceType, reason: nil)
    }

    private func cleanupRemoteTransfer(
        torrentId: String,
        on service: any DebridServiceProtocol,
        serviceType: DebridServiceType,
        reason: Error?
    ) async {
        do {
            try await service.cleanupRemoteTransfer(torrentId: torrentId)
        } catch {
            if let reason {
                Self.logger.error("Remote cleanup failed for \(serviceType.rawValue, privacy: .public) after \(reason.localizedDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                Self.logger.error("Remote cleanup failed for \(serviceType.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func orderedServiceTypes(preferredService: DebridServiceType? = nil) -> [DebridServiceType] {
        var ordered = services.keys.sorted { lhs, rhs in
            let lhsPriority = servicePriority[lhs] ?? Int.max
            let rhsPriority = servicePriority[rhs] ?? Int.max
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.rawValue < rhs.rawValue
        }

        if let preferredService, let preferredIndex = ordered.firstIndex(of: preferredService) {
            ordered.remove(at: preferredIndex)
            ordered.insert(preferredService, at: 0)
        }

        return ordered
    }

    private static func normalizedCacheHashes(_ hashes: [String]) -> [String] {
        var orderedHashes: [String] = []
        var seen: Set<String> = []

        for hash in hashes {
            let normalized = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            orderedHashes.append(normalized)
        }

        return orderedHashes
    }

    private static func chunked(_ hashes: [String], size: Int) -> [[String]] {
        guard size > 0, !hashes.isEmpty else { return [] }

        var batches: [[String]] = []
        batches.reserveCapacity((hashes.count + size - 1) / size)

        var start = 0
        while start < hashes.count {
            let end = min(start + size, hashes.count)
            batches.append(Array(hashes[start..<end]))
            start = end
        }

        return batches
    }

    private func shouldFailover(from error: Error) -> Bool {
        if let debridError = error as? DebridError {
            switch debridError {
            case .invalidHash:
                return false
            default:
                return true
            }
        }
        return true
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

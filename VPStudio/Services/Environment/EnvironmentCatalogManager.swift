import Foundation
import ImageIO
#if os(visionOS)
import RealityKit
#endif

enum EnvironmentCatalogError: LocalizedError {
    case unsupportedFileType
    case missingFile
    case invalidAsset
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported environment file type. Use .usdz, .reality, .hdr, or .exr files."
        case .missingFile:
            return "Selected environment file could not be read."
        case .invalidAsset:
            return "Environment file could not be loaded by RealityKit."
        case .downloadFailed(let reason):
            return "Environment download failed: \(reason)"
        }
    }
}

actor EnvironmentCatalogManager {
    typealias RemoteDataFetcher = @Sendable (URL) async throws -> (Data, URLResponse)

    private let database: DatabaseManager
    private let fileManager: FileManager
    private let environmentsDirectory: URL
    private let assetValidator: @Sendable (URL) async -> Bool
    private let remoteDataFetcher: RemoteDataFetcher

    private static let supportedExtensions: Set<String> = ["usdz", "reality", "hdr", "exr"]

    private static let hdriExtensions: Set<String> = ["hdr", "exr"]

    private static let curatedDefaults: [EnvironmentAsset] = []

    /// Validated URL from a hardcoded string — crashes with a descriptive message instead of bare `!`
    private static func presetURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid hardcoded preset URL: \(string)")
        }
        return url
    }

    private static let curatedRemotePresets: [CuratedEnvironmentPreset] = [
        CuratedEnvironmentPreset(
            id: "polyhaven-pretville-cinema",
            name: "Pretville Cinema",
            description: "Vintage cinema interior with warm projection lighting. CC0 HDRI panorama.",
            provider: .polyHaven,
            downloadURL: presetURL("https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/pretville_cinema_4k.hdr"),
            sourceAttributionURL: "https://polyhaven.com/a/pretville_cinema",
            licenseName: "CC0 1.0 Universal"
        ),
        CuratedEnvironmentPreset(
            id: "polyhaven-cinema-hall",
            name: "Cinema Hall",
            description: "Grand cinema auditorium with atmospheric house lights. CC0 HDRI panorama.",
            provider: .polyHaven,
            downloadURL: presetURL("https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/4k/cinema_hall_4k.hdr"),
            sourceAttributionURL: "https://polyhaven.com/a/cinema_hall",
            licenseName: "CC0 1.0 Universal"
        ),
    ]

    private static let builtInImmersiveSpaces: Set<String> = []

    nonisolated static var onlinePresets: [CuratedEnvironmentPreset] {
        curatedRemotePresets
    }

    init(
        database: DatabaseManager,
        fileManager: FileManager = .default,
        environmentsDirectory: URL? = nil,
        assetValidator: (@Sendable (URL) async -> Bool)? = nil,
        remoteDataFetcher: RemoteDataFetcher? = nil
    ) {
        self.database = database
        self.fileManager = fileManager
        self.assetValidator = assetValidator ?? Self.defaultAssetValidator
        self.remoteDataFetcher = remoteDataFetcher ?? { url in
            try await URLSession.shared.data(from: url)
        }

        if let environmentsDirectory {
            self.environmentsDirectory = environmentsDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.environmentsDirectory = appSupport
                .appendingPathComponent("VPStudio", isDirectory: true)
                .appendingPathComponent("Environments", isDirectory: true)
        }
    }

    func bootstrapCuratedAssets() async throws {
        var existing = try await database.fetchEnvironmentAssets()
        let curatedIDs = Set(Self.curatedDefaults.map(\.id))

        // Remove bundled assets that are no longer in the curated catalog.
        for staleBundled in existing where staleBundled.sourceType == .bundled && !curatedIDs.contains(staleBundled.id) {
            try await database.deleteEnvironmentAsset(id: staleBundled.id)
        }

        // Remove imported assets whose backing files have been deleted —
        // e.g. after an app reinstall, Application Support wipe, or manual
        // deletion. Without this, the environment list shows orphaned entries
        // that open a blank immersive space.
        existing = try await database.fetchEnvironmentAssets()
        for asset in existing where asset.sourceType == .imported {
            guard !asset.assetPath.hasPrefix("bundle://") else { continue }
            let fileURL = URL(fileURLWithPath: asset.assetPath)
            if !fileManager.fileExists(atPath: fileURL.path) {
                try await database.deleteEnvironmentAsset(id: asset.id)
            }
        }

        existing = try await database.fetchEnvironmentAssets()
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for curated in Self.curatedDefaults {
            if let current = existingByID[curated.id] {
                if current.sourceType != .bundled
                    || current.assetPath != curated.assetPath
                    || current.licenseName != curated.licenseName
                    || current.sourceAttributionURL != curated.sourceAttributionURL
                    || current.previewImagePath != curated.previewImagePath {
                    var updated = current
                    updated.sourceType = .bundled
                    updated.assetPath = curated.assetPath
                    updated.licenseName = curated.licenseName
                    updated.sourceAttributionURL = curated.sourceAttributionURL
                    updated.previewImagePath = curated.previewImagePath
                    try await database.saveEnvironmentAsset(updated)
                }
            } else {
                try await database.saveEnvironmentAsset(curated)
            }
        }

        existing = try await database.fetchEnvironmentAssets()
        if !existing.contains(where: { $0.isActive }),
           let defaultAssetID = Self.curatedDefaults.first?.id ?? existing.first?.id {
            try await database.setActiveEnvironmentAsset(id: defaultAssetID)
        }

        // Backfill yaw offsets for any HDRI assets that were imported before
        // the analyzer was added (hdriYawOffset == nil).
        existing = try await database.fetchEnvironmentAssets()
        for asset in existing where asset.hdriYawOffset == nil {
            let ext = URL(fileURLWithPath: asset.assetPath).pathExtension.lowercased()
            guard Self.hdriExtensions.contains(ext) else { continue }
            let fileURL = URL(fileURLWithPath: asset.assetPath)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            if let yaw = await HDRIOrientationAnalyzer.detectScreenYaw(at: fileURL) {
                var updated = asset
                updated.hdriYawOffset = yaw
                try await database.saveEnvironmentAsset(updated)
            }
        }

        notifyEnvironmentsChanged()
    }

    func fetchAssets() async throws -> [EnvironmentAsset] {
        try await database.fetchEnvironmentAssets()
    }

    func activeAsset() async throws -> EnvironmentAsset? {
        try await database.fetchActiveEnvironmentAsset()
    }

    func activateAsset(id: String) async throws {
        try await database.setActiveEnvironmentAsset(id: id)
        notifyEnvironmentsChanged()
    }

    func importEnvironment(from sourceURL: URL) async throws -> EnvironmentAsset {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw EnvironmentCatalogError.missingFile
        }

        let ext = sourceURL.pathExtension.lowercased()
        try Self.validateExtension(ext)

        guard await assetValidator(sourceURL) else {
            throw EnvironmentCatalogError.invalidAsset
        }

        return try await persistImportedAsset(
            sourceURL: sourceURL,
            extension: ext,
            preferredName: nil,
            licenseName: "User Imported",
            sourceAttributionURL: nil,
            previewImagePath: nil
        )
    }

    func importCuratedPreset(_ preset: CuratedEnvironmentPreset) async throws -> EnvironmentAsset {
        if let existing = try await database.fetchEnvironmentAssets().first(where: {
            $0.sourceType == .imported
                && $0.name == preset.name
                && $0.sourceAttributionURL == preset.sourceAttributionURL
        }) {
            return existing
        }

        return try await importEnvironment(
            fromRemote: preset.downloadURL,
            preferredName: preset.name,
            licenseName: preset.licenseName,
            sourceAttributionURL: preset.sourceAttributionURL,
            previewImagePath: nil,
            hdriYawOffset: preset.defaultHdriYawOffset
        )
    }

    func importEnvironment(
        fromRemote sourceURL: URL,
        preferredName: String? = nil,
        licenseName: String? = nil,
        sourceAttributionURL: String? = nil,
        previewImagePath: String? = nil,
        hdriYawOffset: Float? = nil
    ) async throws -> EnvironmentAsset {
        let ext = sourceURL.pathExtension.lowercased()
        try Self.validateExtension(ext)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await remoteDataFetcher(sourceURL)
        } catch {
            throw EnvironmentCatalogError.downloadFailed(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw EnvironmentCatalogError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }

        guard !data.isEmpty else {
            throw EnvironmentCatalogError.downloadFailed("No data returned")
        }

        try fileManager.createDirectory(at: environmentsDirectory, withIntermediateDirectories: true)

        let temporaryURL = environmentsDirectory.appendingPathComponent("remote-\(UUID().uuidString).\(ext)")
        try data.write(to: temporaryURL, options: .atomic)
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        guard await assetValidator(temporaryURL) else {
            throw EnvironmentCatalogError.invalidAsset
        }

        return try await persistImportedAsset(
            sourceURL: temporaryURL,
            extension: ext,
            preferredName: preferredName,
            licenseName: licenseName,
            sourceAttributionURL: sourceAttributionURL,
            previewImagePath: previewImagePath,
            hdriYawOffset: hdriYawOffset
        )
    }

    private func persistImportedAsset(
        sourceURL: URL,
        extension ext: String,
        preferredName: String?,
        licenseName: String?,
        sourceAttributionURL: String?,
        previewImagePath: String?,
        hdriYawOffset: Float? = nil
    ) async throws -> EnvironmentAsset {
        try fileManager.createDirectory(at: environmentsDirectory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let cleanedPreferredName = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let cleanedPreferredName, !cleanedPreferredName.isEmpty {
            resolvedName = cleanedPreferredName
        } else {
            resolvedName = sourceName.isEmpty ? "Imported Environment" : sourceName
        }
        let targetURL = environmentsDirectory.appendingPathComponent("\(id).\(ext)", isDirectory: false)
        if fileManager.fileExists(atPath: targetURL.path) {
            // Use replaceItemAt for atomic replacement, avoiding TOCTOU race.
            _ = try fileManager.replaceItemAt(targetURL, withItemAt: sourceURL)
        } else {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }

        // Auto-detect yaw for HDRI files when no explicit offset was provided.
        let resolvedYawOffset: Float?
        if hdriYawOffset == nil, Self.hdriExtensions.contains(ext) {
            resolvedYawOffset = await HDRIOrientationAnalyzer.detectScreenYaw(at: targetURL)
        } else {
            resolvedYawOffset = hdriYawOffset
        }

        let asset = EnvironmentAsset(
            id: id,
            name: resolvedName,
            sourceType: .imported,
            assetPath: targetURL.path,
            thumbnailPath: nil,
            licenseName: licenseName,
            sourceAttributionURL: sourceAttributionURL,
            previewImagePath: previewImagePath,
            hdriYawOffset: resolvedYawOffset,
            createdAt: Date(),
            isActive: false
        )
        try await database.saveEnvironmentAsset(asset)
        notifyEnvironmentsChanged()
        return asset
    }

    func deleteAsset(id: String) async throws {
        guard let existing = try await database.fetchEnvironmentAssets().first(where: { $0.id == id }) else {
            return
        }

        if existing.sourceType == .imported {
            let fileURL = URL(fileURLWithPath: existing.assetPath)
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        try await database.deleteEnvironmentAsset(id: id)

        if existing.isActive,
           let fallback = try await database.fetchEnvironmentAssets().first {
            try await database.setActiveEnvironmentAsset(id: fallback.id)
        }

        notifyEnvironmentsChanged()
    }

    func immersiveSpaceID(for asset: EnvironmentAsset) -> String {
        if asset.sourceType == .bundled, Self.builtInImmersiveSpaces.contains(asset.assetPath) {
            return asset.assetPath
        }

        let ext = URL(fileURLWithPath: asset.assetPath).pathExtension.lowercased()
        if Self.hdriExtensions.contains(ext) {
            return "hdriSkybox"
        }

        return "customEnvironment"
    }

    func resolvedAssetURL(for asset: EnvironmentAsset) -> URL? {
        if asset.assetPath.hasPrefix("bundle://") {
            let relative = String(asset.assetPath.dropFirst("bundle://".count))
            return Self.urlInResourceBundle(relativePath: relative)
        }

        let fileURL = URL(fileURLWithPath: asset.assetPath)
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        return nil
    }

    /// Validates that an environment asset exists and is accessible.
    /// Returns nil if the asset is invalid, or a description of the issue if validation fails.
    func validateAsset(_ asset: EnvironmentAsset) -> String? {
        // Check for empty or invalid asset path
        guard !asset.assetPath.isEmpty else {
            return "Asset path is empty"
        }

        // Handle bundle resources
        if asset.assetPath.hasPrefix("bundle://") {
            let relative = String(asset.assetPath.dropFirst("bundle://".count))
            guard Self.urlInResourceBundle(relativePath: relative) != nil else {
                return "Bundle resource not found: \(relative)"
            }
            return nil
        }

        // Check file existence for imported assets
        let fileURL = URL(fileURLWithPath: asset.assetPath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return "File not found: \(fileURL.lastPathComponent)"
        }

        // Check file is readable
        guard fileManager.isReadableFile(atPath: fileURL.path) else {
            return "File is not readable: \(fileURL.lastPathComponent)"
        }

        // Check file is not empty
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int, fileSize == 0 {
                return "File is empty: \(fileURL.lastPathComponent)"
            }
        } catch {
            return "Could not read file attributes: \(error.localizedDescription)"
        }

        // Validate file extension
        let ext = fileURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            return "Unsupported file type: \(ext)"
        }

        return nil
    }

    private static func urlInResourceBundle(relativePath: String) -> URL? {
        let relative = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = relative.split(separator: "/").map(String.init)
        guard let file = parts.last, !file.isEmpty else { return nil }
        let fileURL = URL(fileURLWithPath: file)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension.isEmpty ? nil : fileURL.pathExtension
        let subdirectory = parts.dropLast().isEmpty ? nil : parts.dropLast().joined(separator: "/")

        return resourceBundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    private static func defaultAssetValidator(url: URL) async -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return false }

        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isReadableKey])
        guard resourceValues?.isReadable == true else { return false }
        let fileSize = resourceValues?.fileSize ?? 0
        guard fileSize > 0 else { return false }

        // HDRI files are validated by checking the image source
        if hdriExtensions.contains(ext) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
            return CGImageSourceGetCount(source) > 0
        }

        #if os(visionOS)
        do {
            _ = try await Entity(contentsOf: url)
            return true
        } catch {
            return false
        }
        #else
        return true
        #endif
    }

    private static func validateExtension(_ ext: String) throws {
        guard supportedExtensions.contains(ext.lowercased()) else {
            throw EnvironmentCatalogError.unsupportedFileType
        }
    }

    nonisolated private func notifyEnvironmentsChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .environmentsDidChange, object: nil)
        }
    }
}

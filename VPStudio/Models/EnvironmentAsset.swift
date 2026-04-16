import Foundation
import GRDB

enum EnvironmentAssetSourceType: String, Codable, Sendable, CaseIterable {
    case bundled
    case imported
}

struct EnvironmentAsset: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "environment_assets"

    var id: String
    var name: String
    var sourceType: EnvironmentAssetSourceType
    var assetPath: String
    var thumbnailPath: String?
    var licenseName: String?
    var sourceAttributionURL: String?
    var previewImagePath: String?
    var hdriYawOffset: Float?
    var createdAt: Date
    var isActive: Bool

    enum Columns: String, ColumnExpression {
        case id, name, sourceType, assetPath, thumbnailPath
        case licenseName, sourceAttributionURL, previewImagePath
        case hdriYawOffset, createdAt, isActive
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.sourceType] = sourceType.rawValue
        container[Columns.assetPath] = assetPath
        container[Columns.thumbnailPath] = thumbnailPath
        container[Columns.licenseName] = licenseName
        container[Columns.sourceAttributionURL] = sourceAttributionURL
        container[Columns.previewImagePath] = previewImagePath
        container[Columns.hdriYawOffset] = hdriYawOffset.map { Double($0) }
        container[Columns.createdAt] = createdAt
        container[Columns.isActive] = isActive
    }

    init(row: Row) {
        id = row[Columns.id]
        name = row[Columns.name]
        sourceType = EnvironmentAssetSourceType(rawValue: row[Columns.sourceType]) ?? .bundled
        assetPath = row[Columns.assetPath]
        thumbnailPath = row[Columns.thumbnailPath]
        licenseName = row[Columns.licenseName]
        sourceAttributionURL = row[Columns.sourceAttributionURL]
        previewImagePath = row[Columns.previewImagePath]
        hdriYawOffset = (row[Columns.hdriYawOffset] as Double?).map { Float($0) }
        createdAt = row[Columns.createdAt]
        isActive = row[Columns.isActive]
    }

    init(
        id: String,
        name: String,
        sourceType: EnvironmentAssetSourceType,
        assetPath: String,
        thumbnailPath: String? = nil,
        licenseName: String? = nil,
        sourceAttributionURL: String? = nil,
        previewImagePath: String? = nil,
        hdriYawOffset: Float? = nil,
        createdAt: Date = Date(),
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sourceType = sourceType
        self.assetPath = assetPath
        self.thumbnailPath = thumbnailPath
        self.licenseName = licenseName
        self.sourceAttributionURL = sourceAttributionURL
        self.previewImagePath = previewImagePath
        self.hdriYawOffset = hdriYawOffset
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

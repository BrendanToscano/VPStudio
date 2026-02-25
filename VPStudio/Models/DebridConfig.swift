import Foundation
import GRDB

enum DebridServiceType: String, Codable, Sendable, CaseIterable, Identifiable {
    case realDebrid = "real_debrid"
    case allDebrid = "all_debrid"
    case premiumize = "premiumize"
    case torBox = "torbox"
    case debridLink = "debrid_link"
    case offcloud = "offcloud"
    case easyNews = "easynews"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .realDebrid: return "Real-Debrid"
        case .allDebrid: return "AllDebrid"
        case .premiumize: return "Premiumize"
        case .torBox: return "TorBox"
        case .debridLink: return "Debrid-Link"
        case .offcloud: return "Offcloud"
        case .easyNews: return "EasyNews"
        }
    }

    var baseURL: String {
        switch self {
        case .realDebrid: return "https://api.real-debrid.com/rest/1.0"
        case .allDebrid: return "https://api.alldebrid.com/v4"
        case .premiumize: return "https://www.premiumize.me/api"
        case .torBox: return "https://api.torbox.app/v1/api"
        case .debridLink: return "https://debrid-link.com/api/v2"
        case .offcloud: return "https://offcloud.com/api"
        case .easyNews: return "https://members.easynews.com"
        }
    }
}

struct DebridConfig: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "debrid_configs"

    var id: String
    var serviceType: DebridServiceType
    var apiTokenRef: String
    var isActive: Bool
    var priority: Int
    var createdAt: Date
    var updatedAt: Date

    enum Columns: String, ColumnExpression {
        case id, serviceType, apiTokenRef, isActive, priority, createdAt, updatedAt
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.serviceType] = serviceType.rawValue
        container[Columns.apiTokenRef] = apiTokenRef
        container[Columns.isActive] = isActive
        container[Columns.priority] = priority
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }

    init(row: Row) throws {
        id = row[Columns.id]
        let typeRaw: String = row[Columns.serviceType]
        serviceType = DebridServiceType(rawValue: typeRaw) ?? .realDebrid
        apiTokenRef = row[Columns.apiTokenRef]
        isActive = row[Columns.isActive]
        priority = row[Columns.priority]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    init(
        id: String = UUID().uuidString,
        serviceType: DebridServiceType,
        apiTokenRef: String,
        isActive: Bool = true,
        priority: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.serviceType = serviceType
        self.apiTokenRef = apiTokenRef
        self.isActive = isActive
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct IndexerConfig: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "indexer_configs"

    var id: String
    var name: String
    var indexerType: IndexerType
    var baseURL: String?
    var apiKey: String?
    var isActive: Bool
    var priority: Int
    var providerSubtype: ProviderSubtype
    var endpointPath: String
    var categoryFilter: String?
    var apiKeyTransport: APIKeyTransport

    enum IndexerType: String, Codable, Sendable, CaseIterable {
        case apiBay = "apibay"
        case yts = "yts"
        case eztv = "eztv"
        case jackett = "jackett"
        case prowlarr = "prowlarr"
        case torznab = "torznab"
        case zilean = "zilean"
        case stremio = "stremio"
    }

    enum ProviderSubtype: String, Codable, Sendable, CaseIterable {
        case jackett
        case prowlarr
        case customTorznab = "custom_torznab"
        case stremioAddon = "stremio_addon"
        case builtIn = "built_in"
    }

    enum APIKeyTransport: String, Codable, Sendable, CaseIterable {
        case query
        case header
    }

    enum Columns: String, ColumnExpression {
        case id, name, indexerType, baseURL, apiKey, isActive, priority
        case providerSubtype, endpointPath, categoryFilter, apiKeyTransport
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.indexerType] = indexerType.rawValue
        container[Columns.baseURL] = baseURL
        container[Columns.apiKey] = apiKey
        container[Columns.isActive] = isActive
        container[Columns.priority] = priority
        container[Columns.providerSubtype] = providerSubtype.rawValue
        container[Columns.endpointPath] = endpointPath
        container[Columns.categoryFilter] = categoryFilter
        container[Columns.apiKeyTransport] = apiKeyTransport.rawValue
    }

    init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name]
        let typeRaw: String = row[Columns.indexerType]
        indexerType = IndexerType(rawValue: typeRaw) ?? .torznab
        baseURL = row[Columns.baseURL]
        apiKey = row[Columns.apiKey]
        isActive = row[Columns.isActive]
        priority = row[Columns.priority]

        if let subtypeRaw: String = row[Columns.providerSubtype],
           let parsedSubtype = ProviderSubtype(rawValue: subtypeRaw) {
            providerSubtype = parsedSubtype
        } else {
            providerSubtype = indexerType.defaultProviderSubtype
        }

        if let endpointPathValue: String = row[Columns.endpointPath], !endpointPathValue.isEmpty {
            endpointPath = endpointPathValue
        } else {
            endpointPath = indexerType.defaultEndpointPath
        }

        categoryFilter = row[Columns.categoryFilter]

        if let transportRaw: String = row[Columns.apiKeyTransport],
           let parsedTransport = APIKeyTransport(rawValue: transportRaw) {
            apiKeyTransport = parsedTransport
        } else {
            apiKeyTransport = indexerType.defaultAPIKeyTransport
        }
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        indexerType: IndexerType,
        baseURL: String? = nil,
        apiKey: String? = nil,
        isActive: Bool = true,
        priority: Int = 0,
        providerSubtype: ProviderSubtype? = nil,
        endpointPath: String? = nil,
        categoryFilter: String? = nil,
        apiKeyTransport: APIKeyTransport? = nil
    ) {
        self.id = id
        self.name = name
        self.indexerType = indexerType
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.isActive = isActive
        self.priority = priority
        self.providerSubtype = providerSubtype ?? indexerType.defaultProviderSubtype
        self.endpointPath = endpointPath ?? indexerType.defaultEndpointPath
        self.categoryFilter = categoryFilter
        self.apiKeyTransport = apiKeyTransport ?? indexerType.defaultAPIKeyTransport
    }
}

extension IndexerConfig.IndexerType {
    var displayName: String {
        switch self {
        case .apiBay:
            return "APiBay"
        case .yts:
            return "YTS"
        case .eztv:
            return "EZTV"
        case .jackett:
            return "Jackett"
        case .prowlarr:
            return "Prowlarr"
        case .torznab:
            return "Torznab"
        case .zilean:
            return "Zilean"
        case .stremio:
            return "Stremio"
        }
    }

    var isBuiltIn: Bool {
        switch self {
        case .apiBay, .yts, .eztv:
            return true
        case .jackett, .prowlarr, .torznab, .zilean, .stremio:
            return false
        }
    }

    fileprivate var defaultProviderSubtype: IndexerConfig.ProviderSubtype {
        switch self {
        case .apiBay, .yts, .eztv:
            return .builtIn
        case .jackett:
            return .jackett
        case .prowlarr:
            return .prowlarr
        case .torznab, .zilean:
            return .customTorznab
        case .stremio:
            return .stremioAddon
        }
    }

    fileprivate var defaultEndpointPath: String {
        switch self {
        case .apiBay, .yts, .eztv:
            return ""
        case .jackett:
            return "/api/v2.0/indexers/all/results/torznab/api"
        case .prowlarr:
            return "/api/v1/search"
        case .torznab, .zilean:
            return "/api"
        case .stremio:
            return "/manifest.json"
        }
    }

    fileprivate var defaultAPIKeyTransport: IndexerConfig.APIKeyTransport {
        switch self {
        case .prowlarr:
            return .header
        default:
            return .query
        }
    }
}

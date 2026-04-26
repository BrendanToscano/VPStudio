import Foundation
import GRDB

// MARK: - Request Type

enum AIRequestType: String, Codable, Sendable, CaseIterable {
    case recommendation
    case ask
    case compare
}

// MARK: - Usage Record

struct AIUsageRecord: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ai_usage_log"

    var id: String
    var provider: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var estimatedCostUSD: Double
    var requestType: String
    var createdAt: Date

    enum Columns: String, ColumnExpression {
        case id, provider, model, inputTokens, outputTokens
        case estimatedCostUSD, requestType, createdAt
    }

    init(
        id: String = UUID().uuidString,
        provider: AIProviderKind,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        estimatedCostUSD: Double,
        requestType: AIRequestType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider.rawValue
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.requestType = requestType.rawValue
        self.createdAt = createdAt
    }

    var providerKind: AIProviderKind? {
        AIProviderKind(rawValue: provider)
    }

    var requestTypeKind: AIRequestType? {
        AIRequestType(rawValue: requestType)
    }
}

// MARK: - Provider Usage

struct ProviderUsage: Sendable, Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var requestCount: Int
}

// MARK: - Usage Summary

struct AIUsageSummary: Sendable, Equatable {
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCostUSD: Double
    let byProvider: [AIProviderKind: ProviderUsage]
    let requestCount: Int

    static let empty = AIUsageSummary(
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalCostUSD: 0,
        byProvider: [:],
        requestCount: 0
    )
}

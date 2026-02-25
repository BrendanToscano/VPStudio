import Foundation
import Testing
@testable import VPStudio

// MARK: - AIUsageRecord Tests

@Suite("AIUsageRecord")
struct AIUsageRecordTests {

    @Test func initSetsAllFields() {
        let record = AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 500,
            outputTokens: 200,
            estimatedCostUSD: 0.0045,
            requestType: .ask
        )
        #expect(record.provider == "anthropic")
        #expect(record.model == "claude-sonnet-4-20250514")
        #expect(record.inputTokens == 500)
        #expect(record.outputTokens == 200)
        #expect(abs(record.estimatedCostUSD - 0.0045) < 0.000001)
        #expect(record.requestType == "ask")
        #expect(!record.id.isEmpty)
    }

    @Test func providerKindConversion() {
        let record = AIUsageRecord(
            provider: .openAI,
            model: "gpt-4o",
            inputTokens: 0,
            outputTokens: 0,
            estimatedCostUSD: 0,
            requestType: .recommendation
        )
        #expect(record.providerKind == .openAI)
    }

    @Test func requestTypeKindConversion() {
        let record = AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 0,
            outputTokens: 0,
            estimatedCostUSD: 0,
            requestType: .compare
        )
        #expect(record.requestTypeKind == .compare)
    }

    @Test func equatable() {
        let id = UUID().uuidString
        let date = Date()
        let a = AIUsageRecord(
            id: id,
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCostUSD: 0.001,
            requestType: .ask,
            createdAt: date
        )
        let b = AIUsageRecord(
            id: id,
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCostUSD: 0.001,
            requestType: .ask,
            createdAt: date
        )
        #expect(a == b)
    }
}

// MARK: - AIUsageSummary Tests

@Suite("AIUsageSummary")
struct AIUsageSummaryTests {

    @Test func emptyIsAllZeros() {
        let s = AIUsageSummary.empty
        #expect(s.totalInputTokens == 0)
        #expect(s.totalOutputTokens == 0)
        #expect(s.totalCostUSD == 0)
        #expect(s.byProvider.isEmpty)
        #expect(s.requestCount == 0)
    }
}

// MARK: - AIRequestType Tests

@Suite("AIRequestType")
struct AIRequestTypeTests {

    @Test func allCasesExist() {
        #expect(AIRequestType.allCases.count == 3)
        #expect(AIRequestType.allCases.contains(.recommendation))
        #expect(AIRequestType.allCases.contains(.ask))
        #expect(AIRequestType.allCases.contains(.compare))
    }

    @Test func rawValuesAreCorrect() {
        #expect(AIRequestType.recommendation.rawValue == "recommendation")
        #expect(AIRequestType.ask.rawValue == "ask")
        #expect(AIRequestType.compare.rawValue == "compare")
    }
}

// MARK: - Database Persistence Tests

@Suite("AIUsageTracking - Database")
struct AIUsageTrackingDatabaseTests {

    private func makeDatabase() async throws -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("usage-test.sqlite")
        let database = try DatabaseManager(path: dbURL.path)
        try await database.migrate()
        return (database, tempDir)
    }

    @Test func saveAndFetchUsageRecord() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let record = AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 1000,
            outputTokens: 500,
            estimatedCostUSD: 0.0105,
            requestType: .ask
        )
        try await db.saveAIUsageRecord(record)

        let fetched = try await db.fetchAIUsageRecords()
        #expect(fetched.count == 1)
        #expect(fetched[0].id == record.id)
        #expect(fetched[0].inputTokens == 1000)
        #expect(fetched[0].outputTokens == 500)
    }

    @Test func fetchRecordsSinceDate() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldDate = Date(timeIntervalSinceNow: -3600)
        let recentDate = Date()

        let oldRecord = AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCostUSD: 0.001,
            requestType: .ask,
            createdAt: oldDate
        )
        let recentRecord = AIUsageRecord(
            provider: .openAI,
            model: "gpt-4o",
            inputTokens: 200,
            outputTokens: 100,
            estimatedCostUSD: 0.002,
            requestType: .recommendation,
            createdAt: recentDate
        )
        try await db.saveAIUsageRecord(oldRecord)
        try await db.saveAIUsageRecord(recentRecord)

        let cutoff = Date(timeIntervalSinceNow: -1800) // 30 min ago
        let results = try await db.fetchAIUsageRecords(since: cutoff)
        #expect(results.count == 1)
        #expect(results[0].model == "gpt-4o")
    }

    @Test func lifetimeSummaryAggregation() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 1000,
            outputTokens: 500,
            estimatedCostUSD: 0.0105,
            requestType: .ask
        ))
        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 2000,
            outputTokens: 1000,
            estimatedCostUSD: 0.021,
            requestType: .recommendation
        ))
        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .openAI,
            model: "gpt-4o",
            inputTokens: 500,
            outputTokens: 250,
            estimatedCostUSD: 0.00375,
            requestType: .ask
        ))

        let summary = try await db.fetchAIUsageSummary()
        #expect(summary.totalInputTokens == 3500)
        #expect(summary.totalOutputTokens == 1750)
        #expect(abs(summary.totalCostUSD - 0.03525) < 0.000001)
        #expect(summary.requestCount == 3)
    }

    @Test func providerBreakdownAccuracy() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 1000,
            outputTokens: 500,
            estimatedCostUSD: 0.0105,
            requestType: .ask
        ))
        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .openAI,
            model: "gpt-4o",
            inputTokens: 2000,
            outputTokens: 1000,
            estimatedCostUSD: 0.015,
            requestType: .recommendation
        ))

        let summary = try await db.fetchAIUsageSummary()
        #expect(summary.byProvider.count == 2)

        let anthropicUsage = summary.byProvider[.anthropic]
        #expect(anthropicUsage != nil)
        #expect(anthropicUsage?.inputTokens == 1000)
        #expect(anthropicUsage?.outputTokens == 500)
        #expect(abs((anthropicUsage?.costUSD ?? 0) - 0.0105) < 0.000001)
        #expect(anthropicUsage?.requestCount == 1)

        let openAIUsage = summary.byProvider[.openAI]
        #expect(openAIUsage != nil)
        #expect(openAIUsage?.inputTokens == 2000)
        #expect(openAIUsage?.outputTokens == 1000)
        #expect(abs((openAIUsage?.costUSD ?? 0) - 0.015) < 0.000001)
        #expect(openAIUsage?.requestCount == 1)
    }

    @Test func sessionSummaryFiltersByDate() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldRecord = AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 5000,
            outputTokens: 2000,
            estimatedCostUSD: 0.045,
            requestType: .ask,
            createdAt: Date(timeIntervalSinceNow: -7200) // 2 hours ago
        )
        let recentRecord = AIUsageRecord(
            provider: .openAI,
            model: "gpt-4o",
            inputTokens: 1000,
            outputTokens: 500,
            estimatedCostUSD: 0.0075,
            requestType: .ask,
            createdAt: Date()
        )
        try await db.saveAIUsageRecord(oldRecord)
        try await db.saveAIUsageRecord(recentRecord)

        let sessionStart = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let session = try await db.fetchAIUsageSummary(since: sessionStart)
        #expect(session.totalInputTokens == 1000)
        #expect(session.totalOutputTokens == 500)
        #expect(session.requestCount == 1)

        let lifetime = try await db.fetchAIUsageSummary()
        #expect(lifetime.totalInputTokens == 6000)
        #expect(lifetime.totalOutputTokens == 2500)
        #expect(lifetime.requestCount == 2)
    }

    @Test func zeroCostForOllamaModels() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cost = AIModelCatalog.estimateCost(
            modelID: "llama3.1",
            inputTokens: 50_000,
            outputTokens: 25_000
        )
        #expect(cost == 0)

        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .ollama,
            model: "llama3.1",
            inputTokens: 50_000,
            outputTokens: 25_000,
            estimatedCostUSD: cost,
            requestType: .ask
        ))

        let summary = try await db.fetchAIUsageSummary()
        #expect(summary.totalCostUSD == 0)
        #expect(summary.totalInputTokens == 50_000)
        #expect(summary.totalOutputTokens == 25_000)
        #expect(summary.requestCount == 1)

        let ollamaUsage = summary.byProvider[.ollama]
        #expect(ollamaUsage?.costUSD == 0)
    }

    @Test func deleteAllUsageRecords() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCostUSD: 0.001,
            requestType: .ask
        ))
        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .openAI,
            model: "gpt-4o",
            inputTokens: 200,
            outputTokens: 100,
            estimatedCostUSD: 0.002,
            requestType: .recommendation
        ))

        var records = try await db.fetchAIUsageRecords()
        #expect(records.count == 2)

        try await db.deleteAllAIUsageRecords()

        records = try await db.fetchAIUsageRecords()
        #expect(records.count == 0)

        let summary = try await db.fetchAIUsageSummary()
        #expect(summary.totalCostUSD == 0)
        #expect(summary.requestCount == 0)
    }

    @Test func emptySummaryForFreshDatabase() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let summary = try await db.fetchAIUsageSummary()
        #expect(summary.totalInputTokens == 0)
        #expect(summary.totalOutputTokens == 0)
        #expect(summary.totalCostUSD == 0)
        #expect(summary.byProvider.isEmpty)
        #expect(summary.requestCount == 0)
    }

    @Test func multipleRecordsSameProvider() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for i in 1...5 {
            try await db.saveAIUsageRecord(AIUsageRecord(
                provider: .anthropic,
                model: "claude-sonnet-4-20250514",
                inputTokens: i * 100,
                outputTokens: i * 50,
                estimatedCostUSD: Double(i) * 0.001,
                requestType: .ask
            ))
        }

        let summary = try await db.fetchAIUsageSummary()
        // Input: 100+200+300+400+500 = 1500
        #expect(summary.totalInputTokens == 1500)
        // Output: 50+100+150+200+250 = 750
        #expect(summary.totalOutputTokens == 750)
        // Cost: 0.001+0.002+0.003+0.004+0.005 = 0.015
        #expect(abs(summary.totalCostUSD - 0.015) < 0.000001)
        #expect(summary.requestCount == 5)
        #expect(summary.byProvider.count == 1)
        #expect(summary.byProvider[.anthropic]?.requestCount == 5)
    }

    @Test func fetchRecordsOrderedByDateDesc() async throws {
        let (db, tempDir) = try await makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let date1 = Date(timeIntervalSinceNow: -3600)
        let date2 = Date(timeIntervalSinceNow: -1800)
        let date3 = Date()

        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .anthropic,
            model: "claude-sonnet-4-20250514",
            inputTokens: 100,
            outputTokens: 50,
            estimatedCostUSD: 0.001,
            requestType: .ask,
            createdAt: date1
        ))
        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .openAI,
            model: "gpt-4o",
            inputTokens: 200,
            outputTokens: 100,
            estimatedCostUSD: 0.002,
            requestType: .recommendation,
            createdAt: date3
        ))
        try await db.saveAIUsageRecord(AIUsageRecord(
            provider: .ollama,
            model: "llama3.1",
            inputTokens: 300,
            outputTokens: 150,
            estimatedCostUSD: 0,
            requestType: .compare,
            createdAt: date2
        ))

        let records = try await db.fetchAIUsageRecords()
        #expect(records.count == 3)
        // Most recent first
        #expect(records[0].model == "gpt-4o")
        #expect(records[1].model == "llama3.1")
        #expect(records[2].model == "claude-sonnet-4-20250514")
    }
}

// MARK: - ProviderUsage Tests

@Suite("ProviderUsage")
struct ProviderUsageTests {

    @Test func equatable() {
        let a = ProviderUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.01, requestCount: 1)
        let b = ProviderUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.01, requestCount: 1)
        #expect(a == b)
    }

    @Test func notEqualForDifferentValues() {
        let a = ProviderUsage(inputTokens: 100, outputTokens: 50, costUSD: 0.01, requestCount: 1)
        let b = ProviderUsage(inputTokens: 200, outputTokens: 50, costUSD: 0.01, requestCount: 1)
        #expect(a != b)
    }
}

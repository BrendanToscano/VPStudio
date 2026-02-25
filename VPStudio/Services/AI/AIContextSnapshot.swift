import Foundation
import GRDB

/// A cached snapshot of assembled AI context, persisted in the database.
/// Only one row is kept (the latest). Rebuilt when stale (>24h) or on significant events.
struct AIContextSnapshot: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ai_context_snapshots"
    static let staleness: TimeInterval = 86400 // 24 hours

    var id: String
    var snapshotJSON: String
    var createdAt: Date

    enum Columns: String, ColumnExpression {
        case id, snapshotJSON, createdAt
    }

    init(id: String = "latest", snapshotJSON: String, createdAt: Date = Date()) {
        self.id = id
        self.snapshotJSON = snapshotJSON
        self.createdAt = createdAt
    }

    /// Decodes the stored JSON into a `ContextSnapshot`.
    func decoded() throws -> AssistantContextAssembler.ContextSnapshot {
        guard let data = snapshotJSON.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "snapshotJSON is not valid UTF-8")
            )
        }
        return try JSONDecoder.iso8601Decoder.decode(AssistantContextAssembler.ContextSnapshot.self, from: data)
    }

    /// Creates a DB record from a `ContextSnapshot`.
    static func from(_ snapshot: AssistantContextAssembler.ContextSnapshot) throws -> AIContextSnapshot {
        let data = try JSONEncoder.iso8601Encoder.encode(snapshot)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(snapshot, .init(codingPath: [], debugDescription: "Failed to encode snapshot to UTF-8"))
        }
        return AIContextSnapshot(snapshotJSON: json, createdAt: snapshot.assembledAt)
    }
}

// MARK: - JSON Coding Helpers

private extension JSONDecoder {
    static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let iso8601Encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

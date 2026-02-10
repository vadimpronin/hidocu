//
//  SQLiteSourceRepository.swift
//  HiDocu
//
//  SQLite implementation of SourceRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteSourceRepository: SourceRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchForDocument(_ documentId: Int64) async throws -> [Source] {
        try await db.asyncRead { database in
            let dtos = try SourceDTO
                .filter(SourceDTO.Columns.documentId == documentId)
                .order(SourceDTO.Columns.sortOrder.asc, SourceDTO.Columns.addedAt.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> Source? {
        try await db.asyncRead { database in
            try SourceDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func insert(_ source: Source) async throws -> Source {
        try await db.asyncWrite { database in
            var dto = SourceDTO(from: source)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func update(_ source: Source) async throws {
        try await db.asyncWrite { database in
            let dto = SourceDTO(from: source)
            try dto.update(database)
        }
    }

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try SourceDTO.deleteOne(database, key: id)
        }
    }

    func updateDiskPathPrefix(oldPrefix: String, newPrefix: String) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: """
                UPDATE sources
                SET disk_path = ? || substr(disk_path, ? + 1)
                WHERE disk_path LIKE ? || '%'
                """,
                arguments: [newPrefix, oldPrefix.count, oldPrefix]
            )
        }
    }

    // MARK: - Synchronous (for startup backfill)

    func fetchAllSync() throws -> [Source] {
        try db.read { database in
            try SourceDTO.fetchAll(database).map { $0.toDomain() }
        }
    }

    func updateSync(_ source: Source) throws {
        try db.write { database in
            let dto = SourceDTO(from: source)
            try dto.update(database)
        }
    }

    func existsByDisplayName(_ displayName: String) async throws -> Bool {
        try await db.asyncRead { database in
            let count = try SourceDTO
                .filter(SourceDTO.Columns.displayName == displayName)
                .fetchCount(database)
            return count > 0
        }
    }

    func fetchDocumentIdsByRecordingIds(_ recordingIds: [Int64]) async throws -> [Int64: Int64] {
        guard !recordingIds.isEmpty else { return [:] }
        return try await db.asyncRead { database in
            let placeholders = recordingIds.map { _ in "?" }.joined(separator: ",")
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT recording_id, document_id FROM sources
                    WHERE recording_id IN (\(placeholders))
                    """,
                arguments: StatementArguments(recordingIds))
            var result: [Int64: Int64] = [:]
            for row in rows {
                if let recId: Int64 = row["recording_id"],
                   let docId: Int64 = row["document_id"] {
                    result[recId] = docId
                }
            }
            return result
        }
    }

    func fetchDocumentInfoByRecordingIds(_ recordingIds: [Int64]) async throws -> [Int64: [DocumentLink]] {
        guard !recordingIds.isEmpty else { return [:] }
        return try await db.asyncRead { database in
            let placeholders = recordingIds.map { _ in "?" }.joined(separator: ",")
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT DISTINCT s.recording_id, d.id AS document_id, d.title
                    FROM sources s
                    JOIN documents d ON d.id = s.document_id
                    WHERE s.recording_id IN (\(placeholders))
                    ORDER BY d.title
                    """,
                arguments: StatementArguments(recordingIds))
            var result: [Int64: [DocumentLink]] = [:]
            for row in rows {
                if let recId: Int64 = row["recording_id"],
                   let docId: Int64 = row["document_id"],
                   let title: String = row["title"] {
                    result[recId, default: []].append(DocumentLink(id: docId, title: title))
                }
            }
            return result
        }
    }
}

//
//  SQLiteTranscriptRepository.swift
//  HiDocu
//
//  SQLite implementation of TranscriptRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteTranscriptRepository: TranscriptRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchForSource(_ sourceId: Int64) async throws -> [Transcript] {
        try await db.asyncRead { database in
            let dtos = try TranscriptDTO
                .filter(TranscriptDTO.Columns.sourceId == sourceId)
                .order(TranscriptDTO.Columns.isPrimary.desc, TranscriptDTO.Columns.id.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> Transcript? {
        try await db.asyncRead { database in
            try TranscriptDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func fetchPrimary(sourceId: Int64) async throws -> Transcript? {
        try await db.asyncRead { database in
            try TranscriptDTO
                .filter(TranscriptDTO.Columns.sourceId == sourceId)
                .filter(TranscriptDTO.Columns.isPrimary == true)
                .fetchOne(database)?
                .toDomain()
        }
    }

    func insert(_ transcript: Transcript) async throws -> Transcript {
        try await db.asyncWrite { database in
            var dto = TranscriptDTO(from: transcript)

            let count = try TranscriptDTO
                .filter(TranscriptDTO.Columns.sourceId == transcript.sourceId)
                .fetchCount(database)

            // Auto-set primary if first transcript
            if count == 0 {
                dto.isPrimary = true
            } else {
                dto.isPrimary = false
            }

            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func update(_ transcript: Transcript) async throws {
        try await db.asyncWrite { database in
            let dto = TranscriptDTO(from: transcript)
            try dto.update(database)
        }
    }

    func delete(id: Int64) async throws {
        try await db.asyncWrite { database in
            guard let dto = try TranscriptDTO.fetchOne(database, key: id) else { return }

            let wasPrimary = dto.isPrimary
            let sourceId = dto.sourceId

            _ = try TranscriptDTO.deleteOne(database, key: id)

            // If deleted was primary, promote the oldest remaining
            if wasPrimary {
                if var oldest = try TranscriptDTO
                    .filter(TranscriptDTO.Columns.sourceId == sourceId)
                    .order(TranscriptDTO.Columns.id.asc)
                    .fetchOne(database) {
                    oldest.isPrimary = true
                    try oldest.update(database)
                }
            }
        }
    }

    func setPrimary(id: Int64, sourceId: Int64) async throws {
        try await db.asyncWrite { database in
            // Clear all primary flags for this source
            try database.execute(
                sql: "UPDATE transcripts SET is_primary = 0 WHERE source_id = ?",
                arguments: [sourceId]
            )
            // Set the target as primary
            try database.execute(
                sql: "UPDATE transcripts SET is_primary = 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func updateFilePathPrefix(oldPrefix: String, newPrefix: String) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: """
                UPDATE transcripts
                SET md_file_path = ? || substr(md_file_path, ? + 1)
                WHERE md_file_path LIKE ? || '%'
                """,
                arguments: [newPrefix, oldPrefix.count, oldPrefix]
            )
        }
    }
}

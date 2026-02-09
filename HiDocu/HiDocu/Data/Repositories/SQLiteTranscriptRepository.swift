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
                .order(TranscriptDTO.Columns.id.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchForDocument(_ documentId: Int64) async throws -> [Transcript] {
        try await db.asyncRead { database in
            let dtos = try TranscriptDTO
                .filter(TranscriptDTO.Columns.documentId == documentId)
                .order(TranscriptDTO.Columns.id.asc)
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

    func fetchPrimaryForDocument(documentId: Int64) async throws -> Transcript? {
        try await db.asyncRead { database in
            try TranscriptDTO
                .filter(TranscriptDTO.Columns.documentId == documentId)
                .filter(TranscriptDTO.Columns.isPrimary == true)
                .fetchOne(database)?
                .toDomain()
        }
    }

    func insert(_ transcript: Transcript, skipAutoPrimary: Bool = false) async throws -> Transcript {
        try await db.asyncWrite { database in
            var dto = TranscriptDTO(from: transcript)

            // Check existing count: prefer document-level if documentId is set
            let count: Int
            if let documentId = transcript.documentId {
                count = try TranscriptDTO
                    .filter(TranscriptDTO.Columns.documentId == documentId)
                    .fetchCount(database)
            } else {
                count = try TranscriptDTO
                    .filter(TranscriptDTO.Columns.sourceId == transcript.sourceId)
                    .fetchCount(database)
            }

            // Auto-set primary if first transcript (unless explicitly skipped)
            if !skipAutoPrimary && count == 0 {
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
            let documentId = dto.documentId

            _ = try TranscriptDTO.deleteOne(database, key: id)

            // If deleted was primary, promote the oldest remaining
            if wasPrimary {
                // Prefer document-level lookup if documentId is set
                let filter: SQLSpecificExpressible
                if let documentId {
                    filter = TranscriptDTO.Columns.documentId == documentId
                } else {
                    filter = TranscriptDTO.Columns.sourceId == sourceId
                }

                if var oldest = try TranscriptDTO
                    .filter(filter)
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

    func setPrimaryForDocument(id: Int64, documentId: Int64) async throws {
        try await db.asyncWrite { database in
            // Clear all primary flags for this document
            try database.execute(
                sql: "UPDATE transcripts SET is_primary = 0 WHERE document_id = ?",
                arguments: [documentId]
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

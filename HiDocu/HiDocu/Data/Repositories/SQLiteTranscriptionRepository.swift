//
//  SQLiteTranscriptionRepository.swift
//  HiDocu
//
//  SQLite implementation of TranscriptionRepository using GRDB.
//

import Foundation
import GRDB

/// SQLite-backed implementation of TranscriptionRepository.
/// Enforces max 5 variants per recording with automatic primary management.
final class SQLiteTranscriptionRepository: TranscriptionRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    // MARK: - Fetch

    func fetchForRecording(_ recordingId: Int64) async throws -> [Transcription] {
        try await db.asyncRead { database in
            let dtos = try TranscriptionDTO
                .filter(TranscriptionDTO.Columns.recordingId == recordingId)
                .order(TranscriptionDTO.Columns.isPrimary.desc, TranscriptionDTO.Columns.id.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> Transcription? {
        try await db.asyncRead { database in
            guard let dto = try TranscriptionDTO.fetchOne(database, key: id) else {
                return nil
            }
            return dto.toDomain()
        }
    }

    func fetchPrimary(recordingId: Int64) async throws -> Transcription? {
        try await db.asyncRead { database in
            let dto = try TranscriptionDTO
                .filter(TranscriptionDTO.Columns.recordingId == recordingId)
                .filter(TranscriptionDTO.Columns.isPrimary == true)
                .fetchOne(database)
            return dto?.toDomain()
        }
    }

    func countForRecording(_ recordingId: Int64) async throws -> Int {
        try await db.asyncRead { database in
            try TranscriptionDTO
                .filter(TranscriptionDTO.Columns.recordingId == recordingId)
                .fetchCount(database)
        }
    }

    // MARK: - Insert

    func insert(_ transcription: Transcription) async throws -> Transcription {
        try await db.asyncWrite { database in
            // Check variant count
            let count = try TranscriptionDTO
                .filter(TranscriptionDTO.Columns.recordingId == transcription.recordingId)
                .fetchCount(database)

            guard count < 5 else {
                throw TranscriptionError.maxVariantsReached
            }

            var dto = TranscriptionDTO(from: transcription)

            // Auto-set primary if first variant; force non-primary otherwise
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

    // MARK: - Update

    func update(_ transcription: Transcription) async throws {
        try await db.asyncWrite { database in
            let dto = TranscriptionDTO(from: transcription)
            try dto.update(database)
        }
    }

    // MARK: - Delete

    func delete(id: Int64) async throws {
        try await db.asyncWrite { database in
            // Fetch the transcription to check if it's primary
            guard let dto = try TranscriptionDTO.fetchOne(database, key: id) else {
                throw TranscriptionError.notFound
            }

            let wasPrimary = dto.isPrimary
            let recordingId = dto.recordingId

            // Delete the variant
            _ = try TranscriptionDTO.deleteOne(database, key: id)

            // If deleted variant was primary, promote the oldest remaining
            if wasPrimary {
                if var oldest = try TranscriptionDTO
                    .filter(TranscriptionDTO.Columns.recordingId == recordingId)
                    .order(TranscriptionDTO.Columns.id.asc)
                    .fetchOne(database) {
                    oldest.isPrimary = true
                    try oldest.update(database)
                }
            }
        }
    }

    // MARK: - Primary Management

    func setPrimary(id: Int64, recordingId: Int64) async throws {
        try await db.asyncWrite { database in
            // Verify the target exists and belongs to this recording
            guard let _ = try TranscriptionDTO
                .filter(TranscriptionDTO.Columns.id == id)
                .filter(TranscriptionDTO.Columns.recordingId == recordingId)
                .fetchOne(database) else {
                throw TranscriptionError.notFound
            }

            // Clear all primary flags for this recording
            try database.execute(
                sql: "UPDATE transcriptions SET is_primary = 0 WHERE recording_id = ?",
                arguments: [recordingId]
            )

            // Set the target as primary
            try database.execute(
                sql: "UPDATE transcriptions SET is_primary = 1 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Segments

    func fetchSegments(transcriptionId: Int64) async throws -> [Segment] {
        try await db.asyncRead { database in
            let dtos = try SegmentDTO
                .filter(SegmentDTO.Columns.transcriptionId == transcriptionId)
                .order(SegmentDTO.Columns.startTimeMs.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func insertSegments(_ segments: [Segment], transcriptionId: Int64) async throws {
        try await db.asyncWrite { database in
            for segment in segments {
                var dto = SegmentDTO(from: segment)
                dto.transcriptionId = transcriptionId
                try dto.insert(database)
            }
        }
    }

    // MARK: - Search

    func search(query: String) async throws -> [Transcription] {
        try await db.asyncRead { database in
            let pattern = "%\(query)%"
            let dtos = try TranscriptionDTO
                .filter(TranscriptionDTO.Columns.fullText.like(pattern))
                .order(TranscriptionDTO.Columns.id.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }
}

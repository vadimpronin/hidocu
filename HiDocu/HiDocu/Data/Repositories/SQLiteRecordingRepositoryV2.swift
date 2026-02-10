//
//  SQLiteRecordingRepositoryV2.swift
//  HiDocu
//
//  SQLite implementation of RecordingRepositoryV2 using GRDB.
//

import Foundation
import GRDB

final class SQLiteRecordingRepositoryV2: RecordingRepositoryV2, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchAll() async throws -> [RecordingV2] {
        try await db.asyncRead { database in
            let dtos = try RecordingV2DTO
                .order(RecordingV2DTO.Columns.createdAt.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> RecordingV2? {
        try await db.asyncRead { database in
            try RecordingV2DTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func fetchByFilename(_ filename: String) async throws -> RecordingV2? {
        try await db.asyncRead { database in
            try RecordingV2DTO
                .filter(RecordingV2DTO.Columns.filename == filename)
                .fetchOne(database)?
                .toDomain()
        }
    }

    func insert(_ recording: RecordingV2) async throws -> RecordingV2 {
        try await db.asyncWrite { database in
            var dto = RecordingV2DTO(from: recording)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try RecordingV2DTO.deleteOne(database, key: id)
        }
    }

    func exists(filename: String, sizeBytes: Int) async throws -> Bool {
        try await db.asyncRead { database in
            let count = try RecordingV2DTO
                .filter(RecordingV2DTO.Columns.filename == filename)
                .filter(RecordingV2DTO.Columns.fileSizeBytes == sizeBytes)
                .fetchCount(database)
            return count > 0
        }
    }

    func observeAll() -> AsyncThrowingStream<[RecordingV2], Error> {
        AsyncThrowingStream { continuation in
            let observation = ValueObservation.tracking { database -> [RecordingV2DTO] in
                try RecordingV2DTO
                    .order(RecordingV2DTO.Columns.createdAt.desc)
                    .fetchAll(database)
            }

            let cancellable = observation.start(in: db.dbPool, scheduling: .async(onQueue: .main)) { error in
                continuation.finish(throwing: error)
            } onChange: { dtos in
                continuation.yield(dtos.map { $0.toDomain() })
            }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    func fetchBySourceId(_ sourceId: Int64) async throws -> [RecordingV2] {
        try await db.asyncRead { database in
            let dtos = try RecordingV2DTO
                .filter(RecordingV2DTO.Columns.recordingSourceId == sourceId)
                .order(RecordingV2DTO.Columns.createdAt.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func existsByFilenameAndSourceId(_ filename: String, sourceId: Int64) async throws -> Bool {
        try await db.asyncRead { database in
            let count = try RecordingV2DTO
                .filter(RecordingV2DTO.Columns.filename == filename)
                .filter(RecordingV2DTO.Columns.recordingSourceId == sourceId)
                .fetchCount(database)
            return count > 0
        }
    }

    func fetchFilenamesForSource(_ sourceId: Int64) async throws -> Set<String> {
        try await db.asyncRead { database in
            let filenames = try String.fetchAll(database,
                sql: "SELECT filename FROM recordings WHERE recording_source_id = ?",
                arguments: [sourceId]
            )
            return Set(filenames)
        }
    }

    func updateSyncStatus(id: Int64, syncStatus: RecordingSyncStatus) async throws {
        _ = try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE recordings SET sync_status = ? WHERE id = ?",
                arguments: [syncStatus.rawValue, id]
            )
        }
    }

    func fetchByFilenameAndSourceId(_ filename: String, sourceId: Int64) async throws -> RecordingV2? {
        try await db.asyncRead { database in
            try RecordingV2DTO
                .filter(RecordingV2DTO.Columns.filename == filename)
                .filter(RecordingV2DTO.Columns.recordingSourceId == sourceId)
                .fetchOne(database)?
                .toDomain()
        }
    }

    func updateAfterImport(id: Int64, filepath: String, syncStatus: RecordingSyncStatus) async throws {
        _ = try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE recordings SET filepath = ?, sync_status = ?, modified_at = ? WHERE id = ?",
                arguments: [filepath, syncStatus.rawValue, Date(), id]
            )
        }
    }

    func deleteOnDeviceOnlyBySourceExcluding(sourceId: Int64, keepFilenames: Set<String>) async throws {
        _ = try await db.asyncWrite { database in
            if keepFilenames.isEmpty {
                try database.execute(
                    sql: "DELETE FROM recordings WHERE recording_source_id = ? AND sync_status = ?",
                    arguments: [sourceId, RecordingSyncStatus.onDeviceOnly.rawValue]
                )
            } else {
                let placeholders = Array(repeating: "?", count: keepFilenames.count).joined(separator: ", ")
                var args: [any DatabaseValueConvertible] = [sourceId, RecordingSyncStatus.onDeviceOnly.rawValue]
                args.append(contentsOf: keepFilenames.sorted())
                try database.execute(
                    sql: "DELETE FROM recordings WHERE recording_source_id = ? AND sync_status = ? AND filename NOT IN (\(placeholders))",
                    arguments: StatementArguments(args)
                )
            }
        }
    }

    func batchInsertAndCleanupDeviceOnly(
        newRecordings: [RecordingV2],
        sourceId: Int64,
        keepFilenames: Set<String>
    ) async throws {
        _ = try await db.asyncWrite { database in
            // Insert new device-only records
            for recording in newRecordings {
                var dto = RecordingV2DTO(from: recording)
                try dto.insert(database)
            }

            // Delete stale on_device_only records not in keepFilenames
            if keepFilenames.isEmpty {
                try database.execute(
                    sql: "DELETE FROM recordings WHERE recording_source_id = ? AND sync_status = ?",
                    arguments: [sourceId, RecordingSyncStatus.onDeviceOnly.rawValue]
                )
            } else {
                let placeholders = Array(repeating: "?", count: keepFilenames.count).joined(separator: ", ")
                var args: [any DatabaseValueConvertible] = [sourceId, RecordingSyncStatus.onDeviceOnly.rawValue]
                args.append(contentsOf: keepFilenames.sorted())
                try database.execute(
                    sql: "DELETE FROM recordings WHERE recording_source_id = ? AND sync_status = ? AND filename NOT IN (\(placeholders))",
                    arguments: StatementArguments(args)
                )
            }
        }
    }

    func observeBySourceId(_ sourceId: Int64) -> AsyncThrowingStream<[RecordingV2], Error> {
        AsyncThrowingStream { continuation in
            let observation = ValueObservation.tracking { database -> [RecordingV2DTO] in
                try RecordingV2DTO
                    .filter(RecordingV2DTO.Columns.recordingSourceId == sourceId)
                    .order(RecordingV2DTO.Columns.createdAt.desc)
                    .fetchAll(database)
            }

            let cancellable = observation.start(in: self.db.dbPool, scheduling: .async(onQueue: .main)) { error in
                continuation.finish(throwing: error)
            } onChange: { dtos in
                continuation.yield(dtos.map { $0.toDomain() })
            }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

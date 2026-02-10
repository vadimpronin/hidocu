//
//  SQLiteRecordingSourceRepository.swift
//  HiDocu
//
//  SQLite implementation of RecordingSourceRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteRecordingSourceRepository: RecordingSourceRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchAll() async throws -> [RecordingSource] {
        try await db.asyncRead { database in
            let dtos = try RecordingSourceDTO
                .order(RecordingSourceDTO.Columns.createdAt.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> RecordingSource? {
        try await db.asyncRead { database in
            try RecordingSourceDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func fetchByUniqueIdentifier(_ identifier: String) async throws -> RecordingSource? {
        try await db.asyncRead { database in
            try RecordingSourceDTO
                .filter(RecordingSourceDTO.Columns.uniqueIdentifier == identifier)
                .fetchOne(database)?
                .toDomain()
        }
    }

    func insert(_ source: RecordingSource) async throws -> RecordingSource {
        try await db.asyncWrite { database in
            var dto = RecordingSourceDTO(from: source)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func update(_ source: RecordingSource) async throws {
        try await db.asyncWrite { database in
            let dto = RecordingSourceDTO(from: source)
            try dto.update(database)
        }
    }

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try RecordingSourceDTO.deleteOne(database, key: id)
        }
    }

    func observeAll() -> AsyncThrowingStream<[RecordingSource], Error> {
        AsyncThrowingStream { continuation in
            let observation = ValueObservation.tracking { database -> [RecordingSourceDTO] in
                try RecordingSourceDTO
                    .order(RecordingSourceDTO.Columns.createdAt.asc)
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

    func updateLastSeen(id: Int64, at date: Date) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE recording_sources SET last_seen_at = ? WHERE id = ?",
                arguments: [date, id]
            )
        }
    }

    func updateLastSynced(id: Int64, at date: Date) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE recording_sources SET last_synced_at = ? WHERE id = ?",
                arguments: [date, id]
            )
        }
    }
}

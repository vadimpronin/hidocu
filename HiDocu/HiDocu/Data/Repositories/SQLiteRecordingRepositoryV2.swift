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
}

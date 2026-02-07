//
//  SQLiteDeletionLogRepository.swift
//  HiDocu
//
//  SQLite implementation of DeletionLogRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteDeletionLogRepository: DeletionLogRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchAll() async throws -> [DeletionLogEntry] {
        try await db.asyncRead { database in
            let dtos = try DeletionLogDTO
                .order(DeletionLogDTO.Columns.deletedAt.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> DeletionLogEntry? {
        try await db.asyncRead { database in
            try DeletionLogDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func insert(_ entry: DeletionLogEntry) async throws -> DeletionLogEntry {
        try await db.asyncWrite { database in
            var dto = DeletionLogDTO(from: entry)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try DeletionLogDTO.deleteOne(database, key: id)
        }
    }

    func fetchExpired() async throws -> [DeletionLogEntry] {
        try await db.asyncRead { database in
            let dtos = try DeletionLogDTO
                .filter(DeletionLogDTO.Columns.expiresAt < Date())
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func deleteAll() async throws {
        _ = try await db.asyncWrite { database in
            try DeletionLogDTO.deleteAll(database)
        }
    }
}

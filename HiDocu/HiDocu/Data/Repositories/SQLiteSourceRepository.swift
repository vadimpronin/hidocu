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

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try SourceDTO.deleteOne(database, key: id)
        }
    }
}

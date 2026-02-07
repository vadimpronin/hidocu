//
//  SQLiteAPILogRepository.swift
//  HiDocu
//
//  SQLite implementation of APILogRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteAPILogRepository: APILogRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func insert(_ entry: APILogEntry) async throws -> APILogEntry {
        try await db.asyncWrite { database in
            var dto = APILogDTO(from: entry)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func fetchRecent(limit: Int) async throws -> [APILogEntry] {
        try await db.asyncRead { database in
            let dtos = try APILogDTO
                .order(APILogDTO.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchByDocument(documentId: Int64) async throws -> [APILogEntry] {
        try await db.asyncRead { database in
            let dtos = try APILogDTO
                .filter(APILogDTO.Columns.documentId == documentId)
                .order(APILogDTO.Columns.timestamp.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }
}

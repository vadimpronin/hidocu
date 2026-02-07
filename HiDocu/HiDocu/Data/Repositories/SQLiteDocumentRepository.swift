//
//  SQLiteDocumentRepository.swift
//  HiDocu
//
//  SQLite implementation of DocumentRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteDocumentRepository: DocumentRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchAll(folderId: Int64?) async throws -> [Document] {
        try await db.asyncRead { database in
            let dtos: [DocumentDTO]
            if let folderId {
                dtos = try DocumentDTO
                    .filter(DocumentDTO.Columns.folderId == folderId)
                    .order(DocumentDTO.Columns.createdAt.desc)
                    .fetchAll(database)
            } else {
                dtos = try DocumentDTO
                    .filter(DocumentDTO.Columns.folderId == nil)
                    .order(DocumentDTO.Columns.createdAt.desc)
                    .fetchAll(database)
            }
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchAllRecursive(folderIds: [Int64]) async throws -> [Document] {
        guard !folderIds.isEmpty else { return [] }
        return try await db.asyncRead { database in
            let dtos = try DocumentDTO
                .filter(folderIds.contains(DocumentDTO.Columns.folderId))
                .order(DocumentDTO.Columns.createdAt.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchAllDocuments() async throws -> [Document] {
        try await db.asyncRead { database in
            let dtos = try DocumentDTO
                .order(DocumentDTO.Columns.createdAt.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> Document? {
        try await db.asyncRead { database in
            try DocumentDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func insert(_ document: Document) async throws -> Document {
        try await db.asyncWrite { database in
            var dto = DocumentDTO(from: document)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func update(_ document: Document) async throws {
        try await db.asyncWrite { database in
            let dto = DocumentDTO(from: document)
            try dto.update(database)
        }
    }

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try DocumentDTO.deleteOne(database, key: id)
        }
    }

    func moveDocument(id: Int64, toFolderId: Int64?) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE documents SET folder_id = ?, modified_at = ? WHERE id = ?",
                arguments: [toFolderId, Date(), id]
            )
        }
    }

    func observeAll(folderId: Int64?) -> AsyncThrowingStream<[Document], Error> {
        AsyncThrowingStream { continuation in
            let observation = ValueObservation.tracking { database -> [DocumentDTO] in
                if let folderId {
                    return try DocumentDTO
                        .filter(DocumentDTO.Columns.folderId == folderId)
                        .order(DocumentDTO.Columns.createdAt.desc)
                        .fetchAll(database)
                } else {
                    return try DocumentDTO
                        .filter(DocumentDTO.Columns.folderId == nil)
                        .order(DocumentDTO.Columns.createdAt.desc)
                        .fetchAll(database)
                }
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

    func observeAllDocuments() -> AsyncThrowingStream<[Document], Error> {
        AsyncThrowingStream { continuation in
            let observation = ValueObservation.tracking { database -> [DocumentDTO] in
                try DocumentDTO
                    .order(DocumentDTO.Columns.createdAt.desc)
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

//
//  SQLiteFolderRepository.swift
//  HiDocu
//
//  SQLite implementation of FolderRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteFolderRepository: FolderRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchAll() async throws -> [Folder] {
        try await db.asyncRead { database in
            let dtos = try FolderDTO
                .order(FolderDTO.Columns.sortOrder.asc, FolderDTO.Columns.name.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchChildren(parentId: Int64?) async throws -> [Folder] {
        try await db.asyncRead { database in
            let dtos: [FolderDTO]
            if let parentId {
                dtos = try FolderDTO
                    .filter(FolderDTO.Columns.parentId == parentId)
                    .order(FolderDTO.Columns.sortOrder.asc, FolderDTO.Columns.name.asc)
                    .fetchAll(database)
            } else {
                dtos = try FolderDTO
                    .filter(FolderDTO.Columns.parentId == nil)
                    .order(FolderDTO.Columns.sortOrder.asc, FolderDTO.Columns.name.asc)
                    .fetchAll(database)
            }
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> Folder? {
        try await db.asyncRead { database in
            try FolderDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func insert(_ folder: Folder) async throws -> Folder {
        try await db.asyncWrite { database in
            var dto = FolderDTO(from: folder)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func update(_ folder: Folder) async throws {
        try await db.asyncWrite { database in
            let dto = FolderDTO(from: folder)
            try dto.update(database)
        }
    }

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try FolderDTO.deleteOne(database, key: id)
        }
    }

    func moveFolder(id: Int64, toParentId: Int64?) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE folders SET parent_id = ?, modified_at = ? WHERE id = ?",
                arguments: [toParentId, Date(), id]
            )
        }
    }

    func fetchDescendantIds(rootId: Int64) async throws -> [Int64] {
        try await db.asyncRead { database in
            var result: [Int64] = []
            var queue: [Int64] = [rootId]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                result.append(current)
                let children = try FolderDTO
                    .filter(FolderDTO.Columns.parentId == current)
                    .fetchAll(database)
                queue.append(contentsOf: children.compactMap(\.id))
            }
            return result
        }
    }

    func observeAll() -> AsyncThrowingStream<[Folder], Error> {
        AsyncThrowingStream { continuation in
            let observation = ValueObservation.tracking { database -> [FolderDTO] in
                try FolderDTO
                    .order(FolderDTO.Columns.sortOrder.asc, FolderDTO.Columns.name.asc)
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

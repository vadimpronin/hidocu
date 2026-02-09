//
//  SQLiteLLMJobRepository.swift
//  HiDocu
//
//  SQLite implementation of LLMJobRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteLLMJobRepository: LLMJobRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func insert(_ job: LLMJob) async throws -> LLMJob {
        try await db.asyncWrite { database in
            var dto = LLMJobDTO(from: job)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func update(_ job: LLMJob) async throws {
        try await db.asyncWrite { database in
            let dto = LLMJobDTO(from: job)
            try dto.update(database)
        }
    }

    func fetchById(_ id: Int64) async throws -> LLMJob? {
        try await db.asyncRead { database in
            try LLMJobDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func fetchPending(limit: Int) async throws -> [LLMJob] {
        try await db.asyncRead { database in
            let now = Date()
            let dtos = try LLMJobDTO
                .filter(
                    LLMJobDTO.Columns.status == LLMJobStatus.pending.rawValue &&
                    (LLMJobDTO.Columns.nextRetryAt == nil || LLMJobDTO.Columns.nextRetryAt <= now)
                )
                .order(
                    LLMJobDTO.Columns.priority.desc,
                    LLMJobDTO.Columns.createdAt.asc
                )
                .limit(limit)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchRetryable(now: Date) async throws -> [LLMJob] {
        try await db.asyncRead { database in
            let dtos = try LLMJobDTO
                .filter(
                    LLMJobDTO.Columns.status == LLMJobStatus.pending.rawValue &&
                    LLMJobDTO.Columns.nextRetryAt != nil &&
                    LLMJobDTO.Columns.nextRetryAt <= now
                )
                .order(
                    LLMJobDTO.Columns.priority.desc,
                    LLMJobDTO.Columns.createdAt.asc
                )
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchActive() async throws -> [LLMJob] {
        try await db.asyncRead { database in
            let dtos = try LLMJobDTO
                .filter(LLMJobDTO.Columns.status == LLMJobStatus.running.rawValue)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchForDocument(_ documentId: Int64) async throws -> [LLMJob] {
        try await db.asyncRead { database in
            let dtos = try LLMJobDTO
                .filter(LLMJobDTO.Columns.documentId == documentId)
                .order(LLMJobDTO.Columns.createdAt.desc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func cancelForDocument(_ documentId: Int64) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: """
                    UPDATE llm_jobs
                    SET status = ?
                    WHERE document_id = ? AND status IN (?, ?)
                    """,
                arguments: [
                    LLMJobStatus.cancelled.rawValue,
                    documentId,
                    LLMJobStatus.pending.rawValue,
                    LLMJobStatus.running.rawValue
                ]
            )
        }
    }

    func deleteCompleted(olderThan date: Date) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: """
                    DELETE FROM llm_jobs
                    WHERE status = ? AND completed_at < ?
                    """,
                arguments: [LLMJobStatus.completed.rawValue, date]
            )
        }
    }
}

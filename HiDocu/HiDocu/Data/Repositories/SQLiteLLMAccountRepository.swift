//
//  SQLiteLLMAccountRepository.swift
//  HiDocu
//
//  SQLite implementation of LLMAccountRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteLLMAccountRepository: LLMAccountRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchAll() async throws -> [LLMAccount] {
        try await db.asyncRead { database in
            let dtos = try LLMAccountDTO
                .order(LLMAccountDTO.Columns.provider.asc, LLMAccountDTO.Columns.email.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchAll(provider: LLMProvider) async throws -> [LLMAccount] {
        try await db.asyncRead { database in
            let dtos = try LLMAccountDTO
                .filter(LLMAccountDTO.Columns.provider == provider.rawValue)
                .order(LLMAccountDTO.Columns.email.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchActive(provider: LLMProvider) async throws -> [LLMAccount] {
        try await db.asyncRead { database in
            let now = Date()
            let dtos = try LLMAccountDTO
                .filter(
                    LLMAccountDTO.Columns.provider == provider.rawValue &&
                    LLMAccountDTO.Columns.isActive == true &&
                    (LLMAccountDTO.Columns.pausedUntil == nil || LLMAccountDTO.Columns.pausedUntil <= now)
                )
                .order(LLMAccountDTO.Columns.email.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchById(_ id: Int64) async throws -> LLMAccount? {
        try await db.asyncRead { database in
            try LLMAccountDTO.fetchOne(database, key: id)?.toDomain()
        }
    }

    func fetchByProviderAndEmail(provider: LLMProvider, email: String) async throws -> LLMAccount? {
        try await db.asyncRead { database in
            try LLMAccountDTO
                .filter(LLMAccountDTO.Columns.provider == provider.rawValue && LLMAccountDTO.Columns.email == email)
                .fetchOne(database)?
                .toDomain()
        }
    }

    func insert(_ account: LLMAccount) async throws -> LLMAccount {
        try await db.asyncWrite { database in
            var dto = LLMAccountDTO(from: account)
            try dto.insert(database)
            dto.id = database.lastInsertedRowID
            return dto.toDomain()
        }
    }

    func update(_ account: LLMAccount) async throws {
        try await db.asyncWrite { database in
            let dto = LLMAccountDTO(from: account)
            try dto.update(database)
        }
    }

    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { database in
            try LLMAccountDTO.deleteOne(database, key: id)
        }
    }

    func updateLastUsed(id: Int64) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE llm_accounts SET last_used_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }

    func updatePausedUntil(id: Int64, pausedUntil: Date?) async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: "UPDATE llm_accounts SET paused_until = ? WHERE id = ?",
                arguments: [pausedUntil, id]
            )
        }
    }
}

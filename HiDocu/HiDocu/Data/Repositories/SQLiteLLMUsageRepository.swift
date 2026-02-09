//
//  SQLiteLLMUsageRepository.swift
//  HiDocu
//
//  SQLite implementation of LLMUsageRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteLLMUsageRepository: LLMUsageRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func upsert(_ usage: LLMUsage) async throws -> LLMUsage {
        try await db.asyncWrite { database in
            var dto = LLMUsageDTO(from: usage)

            // Check if record exists
            let existing = try LLMUsageDTO
                .filter(
                    LLMUsageDTO.Columns.accountId == usage.accountId &&
                    LLMUsageDTO.Columns.modelId == usage.modelId
                )
                .fetchOne(database)

            if let existing = existing {
                // Update existing record
                dto.id = existing.id
                try dto.update(database)
            } else {
                // Insert new record
                try dto.insert(database)
                dto.id = database.lastInsertedRowID
            }

            return dto.toDomain()
        }
    }

    func fetchForAccount(accountId: Int64) async throws -> [LLMUsage] {
        try await db.asyncRead { database in
            let dtos = try LLMUsageDTO
                .filter(LLMUsageDTO.Columns.accountId == accountId)
                .order(LLMUsageDTO.Columns.modelId.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchForAccountAndModel(accountId: Int64, modelId: String) async throws -> LLMUsage? {
        try await db.asyncRead { database in
            try LLMUsageDTO
                .filter(
                    LLMUsageDTO.Columns.accountId == accountId &&
                    LLMUsageDTO.Columns.modelId == modelId
                )
                .fetchOne(database)?
                .toDomain()
        }
    }

    func fetchForProvider(provider: LLMProvider) async throws -> [LLMUsage] {
        try await db.asyncRead { database in
            // Join with llm_accounts to filter by provider
            let dtos = try LLMUsageDTO
                .joining(
                    required: LLMUsageDTO
                        .belongsTo(LLMAccountDTO.self, key: "account")
                        .filter(LLMAccountDTO.Columns.provider == provider.rawValue)
                )
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func resetDailyCounters() async throws {
        try await db.asyncWrite { database in
            try database.execute(
                sql: """
                    UPDATE llm_usage
                    SET input_tokens_used = 0,
                        output_tokens_used = 0,
                        request_count = 0,
                        period_start = CURRENT_TIMESTAMP
                    """
            )
        }
    }
}

// MARK: - GRDB Associations

extension LLMUsageDTO {
    static func belongsTo(_ type: LLMAccountDTO.Type, key: String) -> BelongsToAssociation<LLMUsageDTO, LLMAccountDTO> {
        belongsTo(type, using: ForeignKey([Columns.accountId], to: [LLMAccountDTO.Columns.id]))
    }
}

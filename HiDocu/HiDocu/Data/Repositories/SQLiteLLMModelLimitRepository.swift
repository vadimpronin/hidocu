//
//  SQLiteLLMModelLimitRepository.swift
//  HiDocu
//
//  SQLite implementation of LLMModelLimitRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteLLMModelLimitRepository: LLMModelLimitRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func upsert(_ limit: LLMModelLimit) async throws -> LLMModelLimit {
        try await db.asyncWrite { database in
            var dto = LLMModelLimitDTO(from: limit)

            // Check if record exists
            let existing = try LLMModelLimitDTO
                .filter(
                    LLMModelLimitDTO.Columns.provider == limit.provider.rawValue &&
                    LLMModelLimitDTO.Columns.modelId == limit.modelId
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

    func fetchForModel(provider: LLMProvider, modelId: String) async throws -> LLMModelLimit? {
        try await db.asyncRead { database in
            try LLMModelLimitDTO
                .filter(
                    LLMModelLimitDTO.Columns.provider == provider.rawValue &&
                    LLMModelLimitDTO.Columns.modelId == modelId
                )
                .fetchOne(database)?
                .toDomain()
        }
    }

    func fetchAll() async throws -> [LLMModelLimit] {
        try await db.asyncRead { database in
            let dtos = try LLMModelLimitDTO
                .order(
                    LLMModelLimitDTO.Columns.provider.asc,
                    LLMModelLimitDTO.Columns.modelId.asc
                )
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }

    func fetchForProvider(provider: LLMProvider) async throws -> [LLMModelLimit] {
        try await db.asyncRead { database in
            let dtos = try LLMModelLimitDTO
                .filter(LLMModelLimitDTO.Columns.provider == provider.rawValue)
                .order(LLMModelLimitDTO.Columns.modelId.asc)
                .fetchAll(database)
            return dtos.map { $0.toDomain() }
        }
    }
}

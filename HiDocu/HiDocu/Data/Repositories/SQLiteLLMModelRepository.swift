//
//  SQLiteLLMModelRepository.swift
//  HiDocu
//
//  SQLite implementation of LLMModelRepository using GRDB.
//

import Foundation
import GRDB

final class SQLiteLLMModelRepository: LLMModelRepository, Sendable {

    private let db: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.db = databaseManager
    }

    func fetchAllAvailableModels() async throws -> [AvailableModel] {
        try await db.asyncRead { database in
            let rows = try Row.fetchAll(database, sql: """
                WITH provider_counts AS (
                    SELECT provider, COUNT(*) AS total_count
                    FROM llm_accounts
                    WHERE is_active = 1
                    GROUP BY provider
                )
                SELECT
                    m.provider,
                    m.model_id,
                    m.display_name,
                    m.supports_text,
                    m.supports_audio,
                    m.supports_image,
                    m.max_input_tokens,
                    m.max_output_tokens,
                    COALESCE(SUM(CASE WHEN am.is_available = 1 AND a.is_active = 1 THEN 1 ELSE 0 END), 0) AS available_count,
                    COALESCE(pc.total_count, 0) AS total_count
                FROM llm_models m
                LEFT JOIN llm_account_models am ON am.model_id = m.id
                LEFT JOIN llm_accounts a ON a.id = am.account_id
                LEFT JOIN provider_counts pc ON pc.provider = m.provider
                GROUP BY m.id
                ORDER BY m.provider ASC, m.model_id ASC
                """)

            return rows.compactMap { row -> AvailableModel? in
                guard let providerStr = row["provider"] as String?,
                      let provider = LLMProvider(rawValue: providerStr),
                      let modelId = row["model_id"] as String?,
                      let displayName = row["display_name"] as String? else {
                    return nil
                }
                let availableCount: Int = row["available_count"] ?? 0
                let totalCount: Int = row["total_count"] ?? 0
                let supportsText: Bool = row["supports_text"] ?? true
                let supportsAudio: Bool = row["supports_audio"] ?? false
                let supportsImage: Bool = row["supports_image"] ?? false
                let maxInputTokens: Int? = row["max_input_tokens"]
                let maxOutputTokens: Int? = row["max_output_tokens"]

                return AvailableModel(
                    provider: provider,
                    modelId: modelId,
                    displayName: displayName,
                    availableAccountCount: availableCount,
                    totalAccountCount: totalCount,
                    supportsText: supportsText,
                    supportsAudio: supportsAudio,
                    supportsImage: supportsImage,
                    maxInputTokens: maxInputTokens,
                    maxOutputTokens: maxOutputTokens
                )
            }
        }
    }

    func syncModelsForAccount(
        accountId: Int64,
        provider: LLMProvider,
        fetchedModels: [ModelInfo]
    ) async throws {
        try await db.asyncWrite { database in
            let providerStr = provider.rawValue
            let now = Date()
            var upsertedModelIds: Set<Int64> = []

            for modelInfo in fetchedModels {
                // Upsert into llm_models
                let existingModel = try LLMModelDTO
                    .filter(LLMModelDTO.Columns.provider == providerStr)
                    .filter(LLMModelDTO.Columns.modelId == modelInfo.id)
                    .fetchOne(database)

                let modelDbId: Int64
                if var existing = existingModel {
                    existing.displayName = modelInfo.displayName
                    existing.supportsText = modelInfo.supportsText
                    existing.supportsAudio = modelInfo.supportsAudio
                    existing.supportsImage = modelInfo.supportsImage
                    existing.maxInputTokens = modelInfo.maxInputTokens
                    existing.maxOutputTokens = modelInfo.maxOutputTokens
                    existing.lastSeenAt = now
                    try existing.update(database)
                    modelDbId = existing.id!
                } else {
                    let dto = LLMModelDTO(
                        from: LLMModel(
                            id: 0,
                            provider: provider,
                            modelId: modelInfo.id,
                            displayName: modelInfo.displayName,
                            supportsText: modelInfo.supportsText,
                            supportsAudio: modelInfo.supportsAudio,
                            supportsImage: modelInfo.supportsImage,
                            maxInputTokens: modelInfo.maxInputTokens,
                            maxOutputTokens: modelInfo.maxOutputTokens,
                            dailyRequestLimit: nil,
                            tokensPerMinute: nil,
                            firstSeenAt: now,
                            lastSeenAt: now
                        )
                    )
                    try dto.insert(database)
                    modelDbId = database.lastInsertedRowID
                }
                upsertedModelIds.insert(modelDbId)

                // Upsert junction row with is_available = true
                let existingJunction = try LLMAccountModelDTO
                    .filter(LLMAccountModelDTO.Columns.accountId == accountId)
                    .filter(LLMAccountModelDTO.Columns.modelId == modelDbId)
                    .fetchOne(database)

                if var junction = existingJunction {
                    junction.isAvailable = true
                    junction.lastCheckedAt = now
                    try junction.update(database)
                } else {
                    let junction = LLMAccountModelDTO(
                        id: nil,
                        accountId: accountId,
                        modelId: modelDbId,
                        isAvailable: true,
                        lastCheckedAt: now
                    )
                    try junction.insert(database)
                }
            }

            // Mark models NOT in fetchedModels as unavailable for this account+provider
            let allProviderModelIds = try Int64.fetchAll(
                database,
                LLMModelDTO
                    .filter(LLMModelDTO.Columns.provider == providerStr)
                    .select(LLMModelDTO.Columns.id)
            )

            let modelIdsToMarkUnavailable = Array(Set(allProviderModelIds).subtracting(upsertedModelIds))
            if !modelIdsToMarkUnavailable.isEmpty {
                try LLMAccountModelDTO
                    .filter(LLMAccountModelDTO.Columns.accountId == accountId)
                    .filter(modelIdsToMarkUnavailable.contains(LLMAccountModelDTO.Columns.modelId))
                    .updateAll(database,
                        LLMAccountModelDTO.Columns.isAvailable.set(to: false),
                        LLMAccountModelDTO.Columns.lastCheckedAt.set(to: now)
                    )
            }
        }
    }
}

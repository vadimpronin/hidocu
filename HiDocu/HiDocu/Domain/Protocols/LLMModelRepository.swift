//
//  LLMModelRepository.swift
//  HiDocu
//
//  Protocol for persisted LLM model operations.
//

import Foundation

/// Repository for managing persisted LLM models and their account availability.
protocol LLMModelRepository: Sendable {
    /// Fetches all persisted models with per-provider availability counts.
    /// Returns enriched AvailableModel objects including how many active accounts
    /// support each model vs total active accounts for that provider.
    func fetchAllAvailableModels() async throws -> [AvailableModel]

    /// Syncs models returned by a provider API for a specific account.
    /// - Upserts each model in `llm_models` (insert or update display_name + last_seen_at).
    /// - Sets `is_available = true` in junction for returned models.
    /// - Sets `is_available = false` for models NOT returned but previously linked to this account+provider.
    func syncModelsForAccount(
        accountId: Int64,
        provider: LLMProvider,
        fetchedModels: [ModelInfo]
    ) async throws
}

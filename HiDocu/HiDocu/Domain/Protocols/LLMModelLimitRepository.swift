//
//  LLMModelLimitRepository.swift
//  HiDocu
//
//  Protocol for LLM model limits persistence operations.
//

import Foundation

/// Repository for managing LLM model limit records.
protocol LLMModelLimitRepository: Sendable {
    /// Inserts or updates a model limit record.
    /// - Parameter limit: Model limit to upsert
    /// - Returns: Upserted model limit with ID
    /// - Throws: Database errors
    func upsert(_ limit: LLMModelLimit) async throws -> LLMModelLimit

    /// Fetches a model limit for a specific provider and model.
    /// - Parameters:
    ///   - provider: Provider to filter by
    ///   - modelId: Model identifier
    /// - Returns: Model limit if found, nil otherwise
    /// - Throws: Database errors
    func fetchForModel(provider: LLMProvider, modelId: String) async throws -> LLMModelLimit?

    /// Fetches all model limits.
    /// - Returns: Array of all model limits
    /// - Throws: Database errors
    func fetchAll() async throws -> [LLMModelLimit]

    /// Fetches all model limits for a specific provider.
    /// - Parameter provider: Provider to filter by
    /// - Returns: Array of model limits for the provider
    /// - Throws: Database errors
    func fetchForProvider(provider: LLMProvider) async throws -> [LLMModelLimit]
}

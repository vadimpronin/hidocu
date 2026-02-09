//
//  LLMUsageRepository.swift
//  HiDocu
//
//  Protocol for LLM usage tracking persistence operations.
//

import Foundation

/// Repository for managing LLM usage tracking records.
protocol LLMUsageRepository: Sendable {
    /// Inserts or updates a usage record.
    /// - Parameter usage: Usage record to upsert
    /// - Returns: Upserted usage record with ID
    /// - Throws: Database errors
    func upsert(_ usage: LLMUsage) async throws -> LLMUsage

    /// Fetches all usage records for a specific account.
    /// - Parameter accountId: Account identifier
    /// - Returns: Array of usage records for the account
    /// - Throws: Database errors
    func fetchForAccount(accountId: Int64) async throws -> [LLMUsage]

    /// Fetches a usage record for a specific account and model.
    /// - Parameters:
    ///   - accountId: Account identifier
    ///   - modelId: Model identifier
    /// - Returns: Usage record if found, nil otherwise
    /// - Throws: Database errors
    func fetchForAccountAndModel(accountId: Int64, modelId: String) async throws -> LLMUsage?

    /// Fetches all usage records for a specific provider.
    /// - Parameter provider: Provider to filter by
    /// - Returns: Array of usage records for the provider
    /// - Throws: Database errors
    func fetchForProvider(provider: LLMProvider) async throws -> [LLMUsage]

    /// Resets daily counters for all usage records.
    /// Sets input/output tokens and request count to 0, updates period_start to now.
    /// - Throws: Database errors
    func resetDailyCounters() async throws
}

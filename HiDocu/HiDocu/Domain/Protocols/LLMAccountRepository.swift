//
//  LLMAccountRepository.swift
//  HiDocu
//
//  Protocol for LLM account persistence operations.
//

import Foundation

/// Repository for managing LLM account records.
protocol LLMAccountRepository: Sendable {
    /// Fetches all LLM accounts across all providers.
    /// - Returns: Array of all accounts
    /// - Throws: Database errors
    func fetchAll() async throws -> [LLMAccount]

    /// Fetches all accounts for a specific provider.
    /// - Parameter provider: The provider to filter by
    /// - Returns: Array of accounts for the provider
    /// - Throws: Database errors
    func fetchAll(provider: LLMProvider) async throws -> [LLMAccount]

    /// Fetches active accounts for a specific provider.
    /// - Parameter provider: The provider to filter by
    /// - Returns: Array of active accounts
    /// - Throws: Database errors
    func fetchActive(provider: LLMProvider) async throws -> [LLMAccount]

    /// Fetches an account by its ID.
    /// - Parameter id: Account identifier
    /// - Returns: Account if found, nil otherwise
    /// - Throws: Database errors
    func fetchById(_ id: Int64) async throws -> LLMAccount?

    /// Fetches an account by provider and email.
    /// - Parameters:
    ///   - provider: The provider
    ///   - email: User email address
    /// - Returns: Account if found, nil otherwise
    /// - Throws: Database errors
    func fetchByProviderAndEmail(provider: LLMProvider, email: String) async throws -> LLMAccount?

    /// Inserts a new account record.
    /// - Parameter account: Account to insert (ID may be ignored)
    /// - Returns: Inserted account with generated ID
    /// - Throws: Database errors
    func insert(_ account: LLMAccount) async throws -> LLMAccount

    /// Updates an existing account record.
    /// - Parameter account: Account with updated fields
    /// - Throws: Database errors if account doesn't exist
    func update(_ account: LLMAccount) async throws

    /// Deletes an account by ID.
    /// - Parameter id: Account identifier
    /// - Throws: Database errors
    func delete(id: Int64) async throws

    /// Updates the lastUsedAt timestamp for an account.
    /// - Parameter id: Account identifier
    /// - Throws: Database errors if account doesn't exist
    func updateLastUsed(id: Int64) async throws

    /// Updates the pausedUntil timestamp for an account.
    /// - Parameters:
    ///   - id: Account identifier
    ///   - pausedUntil: Date when the pause expires, or nil to unpause
    /// - Throws: Database errors if account doesn't exist
    func updatePausedUntil(id: Int64, pausedUntil: Date?) async throws
}

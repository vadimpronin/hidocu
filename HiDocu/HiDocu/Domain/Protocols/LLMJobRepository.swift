//
//  LLMJobRepository.swift
//  HiDocu
//
//  Protocol for LLM job queue persistence operations.
//

import Foundation

/// Repository for managing LLM job queue records.
protocol LLMJobRepository: Sendable {
    /// Inserts a new job record.
    /// - Parameter job: Job to insert (ID may be ignored)
    /// - Returns: Inserted job with generated ID
    /// - Throws: Database errors
    func insert(_ job: LLMJob) async throws -> LLMJob

    /// Updates an existing job record.
    /// - Parameter job: Job with updated fields
    /// - Throws: Database errors if job doesn't exist
    func update(_ job: LLMJob) async throws

    /// Fetches a job by its ID.
    /// - Parameter id: Job identifier
    /// - Returns: Job if found, nil otherwise
    /// - Throws: Database errors
    func fetchById(_ id: Int64) async throws -> LLMJob?

    /// Fetches pending jobs ordered by priority and creation time.
    /// - Parameter limit: Maximum number of jobs to fetch
    /// - Returns: Array of pending jobs
    /// - Throws: Database errors
    func fetchPending(limit: Int) async throws -> [LLMJob]

    /// Fetches jobs that are ready to be retried (next_retry_at <= now).
    /// - Parameter now: Current timestamp
    /// - Returns: Array of retryable jobs
    /// - Throws: Database errors
    func fetchRetryable(now: Date) async throws -> [LLMJob]

    /// Fetches all currently active (running) jobs.
    /// - Returns: Array of running jobs
    /// - Throws: Database errors
    func fetchActive() async throws -> [LLMJob]

    /// Fetches all jobs for a specific document.
    /// - Parameter documentId: Document identifier
    /// - Returns: Array of jobs for the document
    /// - Throws: Database errors
    func fetchForDocument(_ documentId: Int64) async throws -> [LLMJob]

    /// Cancels all jobs for a specific document.
    /// - Parameter documentId: Document identifier
    /// - Throws: Database errors
    func cancelForDocument(_ documentId: Int64) async throws

    /// Deletes completed jobs older than the specified date.
    /// - Parameter date: Cutoff date for deletion
    /// - Throws: Database errors
    func deleteCompleted(olderThan date: Date) async throws

    /// Clears `nextRetryAt` for all pending jobs of the given provider,
    /// making them immediately eligible for pickup.
    /// - Parameter provider: The provider whose deferred jobs should be unblocked
    /// - Throws: Database errors
    func clearDeferredRetry(provider: LLMProvider) async throws

    /// Fetches recent failed jobs ordered by completion time.
    /// - Parameter limit: Maximum number of jobs to fetch
    /// - Returns: Array of failed jobs, most recent first
    /// - Throws: Database errors
    func fetchRecentFailed(limit: Int) async throws -> [LLMJob]

    /// Fetches recent completed jobs ordered by completion time.
    /// - Parameter limit: Maximum number of jobs to fetch
    /// - Returns: Array of completed jobs, most recent first
    /// - Throws: Database errors
    func fetchRecentCompleted(limit: Int) async throws -> [LLMJob]

    /// Fetches all pending jobs regardless of retry timing (for UI display).
    /// - Parameter limit: Maximum number of jobs to fetch
    /// - Returns: Array of all pending jobs, ordered by priority then creation time
    /// - Throws: Database errors
    func fetchAllPending(limit: Int) async throws -> [LLMJob]
}

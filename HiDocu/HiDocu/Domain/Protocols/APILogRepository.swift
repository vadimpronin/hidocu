//
//  APILogRepository.swift
//  HiDocu
//
//  Protocol for API log persistence operations.
//

import Foundation

/// Repository for managing LLM API call logs.
protocol APILogRepository: Sendable {
    /// Inserts a new API log entry.
    /// - Parameter entry: Log entry to insert (ID may be ignored)
    /// - Returns: Inserted entry with generated ID
    /// - Throws: Database errors
    func insert(_ entry: APILogEntry) async throws -> APILogEntry

    /// Fetches the most recent API log entries.
    /// - Parameter limit: Maximum number of entries to return
    /// - Returns: Array of log entries ordered by timestamp descending
    /// - Throws: Database errors
    func fetchRecent(limit: Int) async throws -> [APILogEntry]

    /// Fetches API log entries associated with a specific document.
    /// - Parameter documentId: Document identifier
    /// - Returns: Array of log entries for the document
    /// - Throws: Database errors
    func fetchByDocument(documentId: Int64) async throws -> [APILogEntry]

    /// Fetches the most recent API log entry for a specific transcript.
    /// - Parameter transcriptId: Transcript identifier
    /// - Returns: Most recent log entry for the transcript, or nil if none exists
    /// - Throws: Database errors
    func fetchLatestForTranscript(transcriptId: Int64) async throws -> APILogEntry?
}

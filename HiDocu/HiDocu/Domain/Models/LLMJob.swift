//
//  LLMJob.swift
//  HiDocu
//
//  Represents a persistent LLM background job in the queue.
//

import Foundation

/// The type of LLM job to execute.
enum LLMJobType: String, Sendable, Codable {
    case transcription
    case summary
    case judge
}

/// The execution status of an LLM job.
enum LLMJobStatus: String, Sendable, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

/// A persistent background job in the LLM processing queue.
struct LLMJob: Identifiable, Sendable, Equatable {
    let id: Int64
    var jobType: LLMJobType
    var status: LLMJobStatus
    var priority: Int
    var provider: LLMProvider
    var model: String
    var accountId: Int64?
    var payload: String // JSON-encoded job-specific payload
    var resultRef: String? // JSON-encoded reference to result (e.g., {"transcript_id": 123})
    var errorMessage: String?
    var attemptCount: Int
    var maxAttempts: Int
    var nextRetryAt: Date?
    var documentId: Int64?
    var sourceId: Int64?
    var transcriptId: Int64?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
}

//
//  APILogEntry.swift
//  HiDocu
//
//  Log entry for LLM API calls for debugging and cost tracking.
//

import Foundation

/// A record of an LLM API call with request/response metadata.
struct APILogEntry: Identifiable, Sendable {
    let id: Int64
    let provider: LLMProvider
    let llmAccountId: Int64?
    let model: String
    let requestPayload: String?
    let responsePayload: String?
    let timestamp: Date
    let documentId: Int64?
    let sourceId: Int64?
    let status: String // "success", "error", "rate_limited"
    let error: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let durationMs: Int?
}

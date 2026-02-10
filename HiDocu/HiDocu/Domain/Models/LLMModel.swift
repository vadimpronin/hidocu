//
//  LLMModel.swift
//  HiDocu
//
//  A persisted LLM model entry from a provider's API.
//

import Foundation

/// A model available from an LLM provider, persisted in the database.
/// Models are never deleted; only their availability per account changes.
struct LLMModel: Identifiable, Sendable, Equatable {
    let id: Int64
    var provider: LLMProvider
    var modelId: String
    var displayName: String
    var supportsText: Bool
    var supportsAudio: Bool
    var supportsImage: Bool
    var maxInputTokens: Int?
    var maxOutputTokens: Int?
    var dailyRequestLimit: Int?
    var tokensPerMinute: Int?
    var firstSeenAt: Date
    var lastSeenAt: Date
}

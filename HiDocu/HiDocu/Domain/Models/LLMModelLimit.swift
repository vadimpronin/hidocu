//
//  LLMModelLimit.swift
//  HiDocu
//
//  Represents static capabilities and limits for a specific LLM model.
//

import Foundation

/// Static capabilities and limits for a specific LLM model.
struct LLMModelLimit: Identifiable, Sendable, Equatable {
    let id: Int64
    var provider: LLMProvider
    var modelId: String
    var maxInputTokens: Int?
    var maxOutputTokens: Int?
    var supportsAudio: Bool
    var supportsImages: Bool
    var dailyRequestLimit: Int?
    var tokensPerMinute: Int?
}

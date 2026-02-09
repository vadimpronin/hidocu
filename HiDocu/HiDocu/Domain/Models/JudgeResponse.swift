//
//  JudgeResponse.swift
//  HiDocu
//
//  Domain model for the LLM judge evaluation response.
//

import Foundation

/// Response from the LLM judge that evaluates transcript variants.
struct JudgeResponse: Codable, Sendable, Equatable {
    let oddReasoning: String
    let oddId: Int64
    let bestReasoning: String
    let bestId: Int64

    enum CodingKeys: String, CodingKey {
        case oddReasoning = "reasoning_about_the_odd_one"
        case oddId = "odd_id"
        case bestReasoning = "reasoning_about_the_best_one"
        case bestId = "best_id"
    }
}

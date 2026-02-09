//
//  LLMUsage.swift
//  HiDocu
//
//  Represents per-account/model usage tracking and quota information.
//

import Foundation

/// Tracks usage and quota information for a specific account+model combination.
struct LLMUsage: Identifiable, Sendable, Equatable {
    let id: Int64
    var accountId: Int64
    var modelId: String
    var remainingFraction: Double? // 0.0-1.0, nil if not available
    var resetAt: Date? // When the quota resets
    var lastCheckedAt: Date
    var inputTokensUsed: Int
    var outputTokensUsed: Int
    var requestCount: Int
    var periodStart: Date // Start of the current tracking period
}

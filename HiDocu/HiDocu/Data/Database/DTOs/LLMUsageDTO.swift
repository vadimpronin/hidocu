//
//  LLMUsageDTO.swift
//  HiDocu
//
//  Data Transfer Object for LLM usage tracking - maps between database and domain model.
//

import Foundation
import GRDB

struct LLMUsageDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "llm_usage"

    var id: Int64?
    var accountId: Int64
    var modelId: String
    var remainingFraction: Double?
    var resetAt: Date?
    var lastCheckedAt: Date
    var inputTokensUsed: Int
    var outputTokensUsed: Int
    var requestCount: Int
    var periodStart: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let accountId = Column(CodingKeys.accountId)
        static let modelId = Column(CodingKeys.modelId)
        static let remainingFraction = Column(CodingKeys.remainingFraction)
        static let resetAt = Column(CodingKeys.resetAt)
        static let lastCheckedAt = Column(CodingKeys.lastCheckedAt)
        static let inputTokensUsed = Column(CodingKeys.inputTokensUsed)
        static let outputTokensUsed = Column(CodingKeys.outputTokensUsed)
        static let requestCount = Column(CodingKeys.requestCount)
        static let periodStart = Column(CodingKeys.periodStart)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case modelId = "model_id"
        case remainingFraction = "remaining_fraction"
        case resetAt = "reset_at"
        case lastCheckedAt = "last_checked_at"
        case inputTokensUsed = "input_tokens_used"
        case outputTokensUsed = "output_tokens_used"
        case requestCount = "request_count"
        case periodStart = "period_start"
    }

    init(from domain: LLMUsage) {
        self.id = domain.id == 0 ? nil : domain.id
        self.accountId = domain.accountId
        self.modelId = domain.modelId
        self.remainingFraction = domain.remainingFraction
        self.resetAt = domain.resetAt
        self.lastCheckedAt = domain.lastCheckedAt
        self.inputTokensUsed = domain.inputTokensUsed
        self.outputTokensUsed = domain.outputTokensUsed
        self.requestCount = domain.requestCount
        self.periodStart = domain.periodStart
    }

    func toDomain() -> LLMUsage {
        LLMUsage(
            id: id ?? 0,
            accountId: accountId,
            modelId: modelId,
            remainingFraction: remainingFraction,
            resetAt: resetAt,
            lastCheckedAt: lastCheckedAt,
            inputTokensUsed: inputTokensUsed,
            outputTokensUsed: outputTokensUsed,
            requestCount: requestCount,
            periodStart: periodStart
        )
    }
}

//
//  LLMModelDTO.swift
//  HiDocu
//
//  Data Transfer Object for persisted LLM models.
//

import Foundation
import GRDB

struct LLMModelDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "llm_models"

    var id: Int64?
    var provider: String
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

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let provider = Column(CodingKeys.provider)
        static let modelId = Column(CodingKeys.modelId)
        static let displayName = Column(CodingKeys.displayName)
        static let supportsText = Column(CodingKeys.supportsText)
        static let supportsAudio = Column(CodingKeys.supportsAudio)
        static let supportsImage = Column(CodingKeys.supportsImage)
        static let maxInputTokens = Column(CodingKeys.maxInputTokens)
        static let maxOutputTokens = Column(CodingKeys.maxOutputTokens)
        static let dailyRequestLimit = Column(CodingKeys.dailyRequestLimit)
        static let tokensPerMinute = Column(CodingKeys.tokensPerMinute)
        static let firstSeenAt = Column(CodingKeys.firstSeenAt)
        static let lastSeenAt = Column(CodingKeys.lastSeenAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case modelId = "model_id"
        case displayName = "display_name"
        case supportsText = "supports_text"
        case supportsAudio = "supports_audio"
        case supportsImage = "supports_image"
        case maxInputTokens = "max_input_tokens"
        case maxOutputTokens = "max_output_tokens"
        case dailyRequestLimit = "daily_request_limit"
        case tokensPerMinute = "tokens_per_minute"
        case firstSeenAt = "first_seen_at"
        case lastSeenAt = "last_seen_at"
    }

    init(from domain: LLMModel) {
        self.id = domain.id == 0 ? nil : domain.id
        self.provider = domain.provider.rawValue
        self.modelId = domain.modelId
        self.displayName = domain.displayName
        self.supportsText = domain.supportsText
        self.supportsAudio = domain.supportsAudio
        self.supportsImage = domain.supportsImage
        self.maxInputTokens = domain.maxInputTokens
        self.maxOutputTokens = domain.maxOutputTokens
        self.dailyRequestLimit = domain.dailyRequestLimit
        self.tokensPerMinute = domain.tokensPerMinute
        self.firstSeenAt = domain.firstSeenAt
        self.lastSeenAt = domain.lastSeenAt
    }

    func toDomain() -> LLMModel {
        LLMModel(
            id: id ?? 0,
            provider: LLMProvider(rawValue: provider) ?? .claude,
            modelId: modelId,
            displayName: displayName,
            supportsText: supportsText,
            supportsAudio: supportsAudio,
            supportsImage: supportsImage,
            maxInputTokens: maxInputTokens,
            maxOutputTokens: maxOutputTokens,
            dailyRequestLimit: dailyRequestLimit,
            tokensPerMinute: tokensPerMinute,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt
        )
    }
}

//
//  LLMModelLimitDTO.swift
//  HiDocu
//
//  Data Transfer Object for LLM model limits - maps between database and domain model.
//

import Foundation
import GRDB

struct LLMModelLimitDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "llm_model_limits"

    var id: Int64?
    var provider: String
    var modelId: String
    var maxInputTokens: Int?
    var maxOutputTokens: Int?
    var supportsAudio: Bool
    var supportsImages: Bool
    var dailyRequestLimit: Int?
    var tokensPerMinute: Int?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let provider = Column(CodingKeys.provider)
        static let modelId = Column(CodingKeys.modelId)
        static let maxInputTokens = Column(CodingKeys.maxInputTokens)
        static let maxOutputTokens = Column(CodingKeys.maxOutputTokens)
        static let supportsAudio = Column(CodingKeys.supportsAudio)
        static let supportsImages = Column(CodingKeys.supportsImages)
        static let dailyRequestLimit = Column(CodingKeys.dailyRequestLimit)
        static let tokensPerMinute = Column(CodingKeys.tokensPerMinute)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case modelId = "model_id"
        case maxInputTokens = "max_input_tokens"
        case maxOutputTokens = "max_output_tokens"
        case supportsAudio = "supports_audio"
        case supportsImages = "supports_images"
        case dailyRequestLimit = "daily_request_limit"
        case tokensPerMinute = "tokens_per_minute"
    }

    init(from domain: LLMModelLimit) {
        self.id = domain.id == 0 ? nil : domain.id
        self.provider = domain.provider.rawValue
        self.modelId = domain.modelId
        self.maxInputTokens = domain.maxInputTokens
        self.maxOutputTokens = domain.maxOutputTokens
        self.supportsAudio = domain.supportsAudio
        self.supportsImages = domain.supportsImages
        self.dailyRequestLimit = domain.dailyRequestLimit
        self.tokensPerMinute = domain.tokensPerMinute
    }

    func toDomain() -> LLMModelLimit {
        LLMModelLimit(
            id: id ?? 0,
            provider: LLMProvider(rawValue: provider) ?? .claude,
            modelId: modelId,
            maxInputTokens: maxInputTokens,
            maxOutputTokens: maxOutputTokens,
            supportsAudio: supportsAudio,
            supportsImages: supportsImages,
            dailyRequestLimit: dailyRequestLimit,
            tokensPerMinute: tokensPerMinute
        )
    }
}

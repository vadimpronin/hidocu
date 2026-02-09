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
    var firstSeenAt: Date
    var lastSeenAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let provider = Column(CodingKeys.provider)
        static let modelId = Column(CodingKeys.modelId)
        static let displayName = Column(CodingKeys.displayName)
        static let firstSeenAt = Column(CodingKeys.firstSeenAt)
        static let lastSeenAt = Column(CodingKeys.lastSeenAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case modelId = "model_id"
        case displayName = "display_name"
        case firstSeenAt = "first_seen_at"
        case lastSeenAt = "last_seen_at"
    }

    init(from domain: LLMModel) {
        self.id = domain.id == 0 ? nil : domain.id
        self.provider = domain.provider.rawValue
        self.modelId = domain.modelId
        self.displayName = domain.displayName
        self.firstSeenAt = domain.firstSeenAt
        self.lastSeenAt = domain.lastSeenAt
    }

    func toDomain() -> LLMModel {
        LLMModel(
            id: id ?? 0,
            provider: LLMProvider(rawValue: provider) ?? .claude,
            modelId: modelId,
            displayName: displayName,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt
        )
    }
}

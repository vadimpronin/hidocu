//
//  LLMAccountModelDTO.swift
//  HiDocu
//
//  Data Transfer Object for the account-model junction table.
//

import Foundation
import GRDB

struct LLMAccountModelDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "llm_account_models"

    var id: Int64?
    var accountId: Int64
    var modelId: Int64
    var isAvailable: Bool
    var lastCheckedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let accountId = Column(CodingKeys.accountId)
        static let modelId = Column(CodingKeys.modelId)
        static let isAvailable = Column(CodingKeys.isAvailable)
        static let lastCheckedAt = Column(CodingKeys.lastCheckedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case modelId = "model_id"
        case isAvailable = "is_available"
        case lastCheckedAt = "last_checked_at"
    }
}

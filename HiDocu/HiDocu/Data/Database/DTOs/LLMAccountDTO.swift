//
//  LLMAccountDTO.swift
//  HiDocu
//
//  Data Transfer Object for LLM accounts - maps between database and domain model.
//

import Foundation
import GRDB

struct LLMAccountDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "llm_accounts"

    var id: Int64?
    var provider: String
    var email: String
    var displayName: String
    var isActive: Bool
    var lastUsedAt: Date?
    var createdAt: Date
    var pausedUntil: Date?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let provider = Column(CodingKeys.provider)
        static let email = Column(CodingKeys.email)
        static let displayName = Column(CodingKeys.displayName)
        static let isActive = Column(CodingKeys.isActive)
        static let lastUsedAt = Column(CodingKeys.lastUsedAt)
        static let createdAt = Column(CodingKeys.createdAt)
        static let pausedUntil = Column(CodingKeys.pausedUntil)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case email
        case displayName = "display_name"
        case isActive = "is_active"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case pausedUntil = "paused_until"
    }

    init(from domain: LLMAccount) {
        self.id = domain.id == 0 ? nil : domain.id
        self.provider = domain.provider.rawValue
        self.email = domain.email
        self.displayName = domain.displayName
        self.isActive = domain.isActive
        self.lastUsedAt = domain.lastUsedAt
        self.createdAt = domain.createdAt
        self.pausedUntil = domain.pausedUntil
    }

    func toDomain() -> LLMAccount {
        LLMAccount(
            id: id ?? 0,
            provider: LLMProvider(rawValue: provider) ?? .claude,
            email: email,
            displayName: displayName,
            isActive: isActive,
            lastUsedAt: lastUsedAt,
            createdAt: createdAt,
            pausedUntil: pausedUntil
        )
    }
}

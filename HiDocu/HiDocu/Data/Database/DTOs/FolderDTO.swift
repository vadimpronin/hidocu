//
//  FolderDTO.swift
//  HiDocu
//
//  Data Transfer Object for folders - maps between database and domain model.
//

import Foundation
import GRDB

struct FolderDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "folders"

    var id: Int64?
    var parentId: Int64?
    var name: String
    var transcriptionContext: String?
    var categorizationContext: String?
    var preferSummary: Bool
    var minimizeBeforeLLM: Bool
    var sortOrder: Int
    var createdAt: Date
    var modifiedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let parentId = Column(CodingKeys.parentId)
        static let name = Column(CodingKeys.name)
        static let transcriptionContext = Column(CodingKeys.transcriptionContext)
        static let categorizationContext = Column(CodingKeys.categorizationContext)
        static let preferSummary = Column(CodingKeys.preferSummary)
        static let minimizeBeforeLLM = Column(CodingKeys.minimizeBeforeLLM)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let createdAt = Column(CodingKeys.createdAt)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case parentId = "parent_id"
        case name
        case transcriptionContext = "transcription_context"
        case categorizationContext = "categorization_context"
        case preferSummary = "prefer_summary"
        case minimizeBeforeLLM = "minimize_before_llm"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(from domain: Folder) {
        self.id = domain.id == 0 ? nil : domain.id
        self.parentId = domain.parentId
        self.name = domain.name
        self.transcriptionContext = domain.transcriptionContext
        self.categorizationContext = domain.categorizationContext
        self.preferSummary = domain.preferSummary
        self.minimizeBeforeLLM = domain.minimizeBeforeLLM
        self.sortOrder = domain.sortOrder
        self.createdAt = domain.createdAt
        self.modifiedAt = domain.modifiedAt
    }

    func toDomain() -> Folder {
        Folder(
            id: id ?? 0,
            parentId: parentId,
            name: name,
            transcriptionContext: transcriptionContext,
            categorizationContext: categorizationContext,
            preferSummary: preferSummary,
            minimizeBeforeLLM: minimizeBeforeLLM,
            sortOrder: sortOrder,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}

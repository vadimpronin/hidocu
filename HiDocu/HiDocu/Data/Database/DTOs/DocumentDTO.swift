//
//  DocumentDTO.swift
//  HiDocu
//
//  Data Transfer Object for documents - maps between database and domain model.
//

import Foundation
import GRDB

struct DocumentDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "documents"

    var id: Int64?
    var folderId: Int64?
    var title: String
    var documentType: String
    var diskPath: String
    var bodyPreview: String?
    var summaryText: String?
    var bodyHash: String?
    var summaryHash: String?
    var preferSummary: Bool
    var minimizeBeforeLLM: Bool
    var createdAt: Date
    var modifiedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let folderId = Column(CodingKeys.folderId)
        static let title = Column(CodingKeys.title)
        static let documentType = Column(CodingKeys.documentType)
        static let diskPath = Column(CodingKeys.diskPath)
        static let bodyPreview = Column(CodingKeys.bodyPreview)
        static let summaryText = Column(CodingKeys.summaryText)
        static let bodyHash = Column(CodingKeys.bodyHash)
        static let summaryHash = Column(CodingKeys.summaryHash)
        static let preferSummary = Column(CodingKeys.preferSummary)
        static let minimizeBeforeLLM = Column(CodingKeys.minimizeBeforeLLM)
        static let createdAt = Column(CodingKeys.createdAt)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case folderId = "folder_id"
        case title
        case documentType = "document_type"
        case diskPath = "disk_path"
        case bodyPreview = "body_preview"
        case summaryText = "summary_text"
        case bodyHash = "body_hash"
        case summaryHash = "summary_hash"
        case preferSummary = "prefer_summary"
        case minimizeBeforeLLM = "minimize_before_llm"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(from domain: Document) {
        self.id = domain.id == 0 ? nil : domain.id
        self.folderId = domain.folderId
        self.title = domain.title
        self.documentType = domain.documentType
        self.diskPath = domain.diskPath
        self.bodyPreview = domain.bodyPreview
        self.summaryText = domain.summaryText
        self.bodyHash = domain.bodyHash
        self.summaryHash = domain.summaryHash
        self.preferSummary = domain.preferSummary
        self.minimizeBeforeLLM = domain.minimizeBeforeLLM
        self.createdAt = domain.createdAt
        self.modifiedAt = domain.modifiedAt
    }

    func toDomain() -> Document {
        Document(
            id: id ?? 0,
            folderId: folderId,
            title: title,
            documentType: documentType,
            diskPath: diskPath,
            bodyPreview: bodyPreview,
            summaryText: summaryText,
            bodyHash: bodyHash,
            summaryHash: summaryHash,
            preferSummary: preferSummary,
            minimizeBeforeLLM: minimizeBeforeLLM,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}

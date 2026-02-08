//
//  TranscriptDTO.swift
//  HiDocu
//
//  Data Transfer Object for transcripts - maps between database and domain model.
//

import Foundation
import GRDB

struct TranscriptDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transcripts"

    var id: Int64?
    var sourceId: Int64
    var documentId: Int64?
    var title: String?
    var fullText: String?
    var mdFilePath: String?
    var isPrimary: Bool
    var createdAt: Date
    var modifiedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let sourceId = Column(CodingKeys.sourceId)
        static let documentId = Column(CodingKeys.documentId)
        static let title = Column(CodingKeys.title)
        static let fullText = Column(CodingKeys.fullText)
        static let mdFilePath = Column(CodingKeys.mdFilePath)
        static let isPrimary = Column(CodingKeys.isPrimary)
        static let createdAt = Column(CodingKeys.createdAt)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId = "source_id"
        case documentId = "document_id"
        case title
        case fullText = "full_text"
        case mdFilePath = "md_file_path"
        case isPrimary = "is_primary"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    init(from domain: Transcript) {
        self.id = domain.id == 0 ? nil : domain.id
        self.sourceId = domain.sourceId
        self.documentId = domain.documentId
        self.title = domain.title
        self.fullText = domain.fullText
        self.mdFilePath = domain.mdFilePath
        self.isPrimary = domain.isPrimary
        self.createdAt = domain.createdAt
        self.modifiedAt = domain.modifiedAt
    }

    func toDomain() -> Transcript {
        Transcript(
            id: id ?? 0,
            sourceId: sourceId,
            documentId: documentId,
            title: title,
            fullText: fullText,
            mdFilePath: mdFilePath,
            isPrimary: isPrimary,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}

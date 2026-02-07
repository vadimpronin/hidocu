//
//  DeletionLogDTO.swift
//  HiDocu
//
//  Data Transfer Object for deletion log entries - maps between database and domain model.
//

import Foundation
import GRDB

struct DeletionLogDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "deletion_log"

    var id: Int64?
    var documentId: Int64
    var documentTitle: String?
    var folderPath: String?
    var deletedAt: Date
    var trashPath: String
    var expiresAt: Date
    var originalCreatedAt: Date?
    var originalModifiedAt: Date?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let documentId = Column(CodingKeys.documentId)
        static let documentTitle = Column(CodingKeys.documentTitle)
        static let folderPath = Column(CodingKeys.folderPath)
        static let deletedAt = Column(CodingKeys.deletedAt)
        static let trashPath = Column(CodingKeys.trashPath)
        static let expiresAt = Column(CodingKeys.expiresAt)
        static let originalCreatedAt = Column(CodingKeys.originalCreatedAt)
        static let originalModifiedAt = Column(CodingKeys.originalModifiedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case documentTitle = "document_title"
        case folderPath = "folder_path"
        case deletedAt = "deleted_at"
        case trashPath = "trash_path"
        case expiresAt = "expires_at"
        case originalCreatedAt = "original_created_at"
        case originalModifiedAt = "original_modified_at"
    }

    init(from domain: DeletionLogEntry) {
        self.id = domain.id == 0 ? nil : domain.id
        self.documentId = domain.documentId
        self.documentTitle = domain.documentTitle
        self.folderPath = domain.folderPath
        self.deletedAt = domain.deletedAt
        self.trashPath = domain.trashPath
        self.expiresAt = domain.expiresAt
        self.originalCreatedAt = domain.originalCreatedAt
        self.originalModifiedAt = domain.originalModifiedAt
    }

    func toDomain() -> DeletionLogEntry {
        DeletionLogEntry(
            id: id ?? 0,
            documentId: documentId,
            documentTitle: documentTitle,
            folderPath: folderPath,
            deletedAt: deletedAt,
            trashPath: trashPath,
            expiresAt: expiresAt,
            originalCreatedAt: originalCreatedAt,
            originalModifiedAt: originalModifiedAt
        )
    }
}

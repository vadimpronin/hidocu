//
//  SourceDTO.swift
//  HiDocu
//
//  Data Transfer Object for sources - maps between database and domain model.
//

import Foundation
import GRDB

struct SourceDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "sources"

    var id: Int64?
    var documentId: Int64
    var sourceType: String
    var recordingId: Int64?
    var diskPath: String
    var displayName: String?
    var sortOrder: Int
    var addedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let documentId = Column(CodingKeys.documentId)
        static let sourceType = Column(CodingKeys.sourceType)
        static let recordingId = Column(CodingKeys.recordingId)
        static let diskPath = Column(CodingKeys.diskPath)
        static let displayName = Column(CodingKeys.displayName)
        static let sortOrder = Column(CodingKeys.sortOrder)
        static let addedAt = Column(CodingKeys.addedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case documentId = "document_id"
        case sourceType = "source_type"
        case recordingId = "recording_id"
        case diskPath = "disk_path"
        case displayName = "display_name"
        case sortOrder = "sort_order"
        case addedAt = "added_at"
    }

    init(from domain: Source) {
        self.id = domain.id == 0 ? nil : domain.id
        self.documentId = domain.documentId
        self.sourceType = domain.sourceType.rawValue
        self.recordingId = domain.recordingId
        self.diskPath = domain.diskPath
        self.displayName = domain.displayName
        self.sortOrder = domain.sortOrder
        self.addedAt = domain.addedAt
    }

    func toDomain() -> Source {
        Source(
            id: id ?? 0,
            documentId: documentId,
            sourceType: SourceType(rawValue: sourceType) ?? .recording,
            recordingId: recordingId,
            diskPath: diskPath,
            displayName: displayName,
            sortOrder: sortOrder,
            addedAt: addedAt
        )
    }
}

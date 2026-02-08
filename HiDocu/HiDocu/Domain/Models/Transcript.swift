//
//  Transcript.swift
//  HiDocu
//
//  Domain model representing a transcript variant for a source.
//

import Foundation

struct Transcript: Identifiable, Sendable, Equatable, Hashable {
    let id: Int64
    let sourceId: Int64
    var documentId: Int64?
    var title: String?
    var fullText: String?
    var mdFilePath: String?
    var isPrimary: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: Int64 = 0,
        sourceId: Int64,
        documentId: Int64? = nil,
        title: String? = nil,
        fullText: String? = nil,
        mdFilePath: String? = nil,
        isPrimary: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.sourceId = sourceId
        self.documentId = documentId
        self.title = title
        self.fullText = fullText
        self.mdFilePath = mdFilePath
        self.isPrimary = isPrimary
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

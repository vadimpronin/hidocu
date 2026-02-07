//
//  Document.swift
//  HiDocu
//
//  Domain model representing a document in the context management system.
//

import Foundation

struct Document: Identifiable, Sendable, Equatable, Hashable {
    let id: Int64
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

    init(
        id: Int64 = 0,
        folderId: Int64? = nil,
        title: String = "Untitled",
        documentType: String = "markdown",
        diskPath: String,
        bodyPreview: String? = nil,
        summaryText: String? = nil,
        bodyHash: String? = nil,
        summaryHash: String? = nil,
        preferSummary: Bool = false,
        minimizeBeforeLLM: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.documentType = documentType
        self.diskPath = diskPath
        self.bodyPreview = bodyPreview
        self.summaryText = summaryText
        self.bodyHash = bodyHash
        self.summaryHash = summaryHash
        self.preferSummary = preferSummary
        self.minimizeBeforeLLM = minimizeBeforeLLM
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

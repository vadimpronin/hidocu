//
//  Document.swift
//  HiDocu
//
//  Domain model representing a document in the context management system.
//

import Foundation
import SwiftUI

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
    var sortOrder: Int
    var createdAt: Date
    var modifiedAt: Date
    var summaryGeneratedAt: Date?
    var summaryModel: String?
    var summaryEdited: Bool

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
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        summaryGeneratedAt: Date? = nil,
        summaryModel: String? = nil,
        summaryEdited: Bool = false
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
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.summaryGeneratedAt = summaryGeneratedAt
        self.summaryModel = summaryModel
        self.summaryEdited = summaryEdited
    }
}

extension Document: DocumentRowDisplayable {
    var date: Date { createdAt }
    var subtext: String? { bodyPreview }
    var statusIcon: String? { "doc.text" }
    var statusColor: Color { .accentColor }
    var isTrashed: Bool { false }
    var daysRemaining: Int? { nil }
}

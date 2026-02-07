//
//  Source.swift
//  HiDocu
//
//  Domain model representing a source attached to a document.
//  Type-agnostic for future extensibility (recording, calendar event, PDF, etc.).
//

import Foundation

enum SourceType: String, Sendable, CaseIterable, Hashable {
    case recording
}

struct Source: Identifiable, Sendable, Equatable, Hashable {
    let id: Int64
    let documentId: Int64
    var sourceType: SourceType
    var recordingId: Int64?
    var diskPath: String
    var displayName: String?
    var sortOrder: Int
    var addedAt: Date

    init(
        id: Int64 = 0,
        documentId: Int64,
        sourceType: SourceType = .recording,
        recordingId: Int64? = nil,
        diskPath: String,
        displayName: String? = nil,
        sortOrder: Int = 0,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.documentId = documentId
        self.sourceType = sourceType
        self.recordingId = recordingId
        self.diskPath = diskPath
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }
}

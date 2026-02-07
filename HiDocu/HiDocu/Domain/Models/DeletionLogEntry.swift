//
//  DeletionLogEntry.swift
//  HiDocu
//
//  Domain model for tracking deleted documents in the trash system.
//

import Foundation

struct DeletionLogEntry: Identifiable, Sendable, Equatable, Hashable {
    let id: Int64
    let documentId: Int64
    var documentTitle: String?
    var folderPath: String?
    var deletedAt: Date
    var trashPath: String
    var expiresAt: Date
    var originalCreatedAt: Date?
    var originalModifiedAt: Date?

    var daysRemaining: Int {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: now, to: expiresAt)
        return max(0, components.day ?? 0)
    }

    init(
        id: Int64 = 0,
        documentId: Int64,
        documentTitle: String? = nil,
        folderPath: String? = nil,
        deletedAt: Date = Date(),
        trashPath: String,
        expiresAt: Date,
        originalCreatedAt: Date? = nil,
        originalModifiedAt: Date? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.documentTitle = documentTitle
        self.folderPath = folderPath
        self.deletedAt = deletedAt
        self.trashPath = trashPath
        self.expiresAt = expiresAt
        self.originalCreatedAt = originalCreatedAt
        self.originalModifiedAt = originalModifiedAt
    }
}

//
//  DeletionLogEntry.swift
//  HiDocu
//
//  Domain model for tracking deleted documents in the trash system.
//

import Foundation
import SwiftUI

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

    var daysRemaining: Int? {
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

extension DeletionLogEntry: DocumentRowDisplayable {
    var title: String { documentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled" }
    var date: Date { deletedAt }
    var subtext: String? { folderPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { "Deleted from \($0)" } }
    var statusIcon: String? { "trash" }
    var statusColor: Color {
        guard let daysRemaining else { return .secondary }
        return daysRemaining < 7 ? .red : .orange
    }
    var isTrashed: Bool { true }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

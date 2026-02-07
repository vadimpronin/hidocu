//
//  Folder.swift
//  HiDocu
//
//  Domain model representing a folder in the context management hierarchy.
//

import Foundation

struct Folder: Identifiable, Sendable, Equatable, Hashable {
    let id: Int64
    var parentId: Int64?
    var name: String
    var transcriptionContext: String?
    var categorizationContext: String?
    var preferSummary: Bool
    var minimizeBeforeLLM: Bool
    var sortOrder: Int
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: Int64 = 0,
        parentId: Int64? = nil,
        name: String,
        transcriptionContext: String? = nil,
        categorizationContext: String? = nil,
        preferSummary: Bool = true,
        minimizeBeforeLLM: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.transcriptionContext = transcriptionContext
        self.categorizationContext = categorizationContext
        self.preferSummary = preferSummary
        self.minimizeBeforeLLM = minimizeBeforeLLM
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

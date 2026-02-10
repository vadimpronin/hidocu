//
//  RecordingSource.swift
//  HiDocu
//
//  Domain model for persistent audio import sources (HiDock devices, manual imports, etc.)
//

import Foundation

/// Type of recording source
enum RecordingSourceType: String, Sendable, CaseIterable, Hashable {
    case hidock
    case upload
    case icloud
}

/// Sync status for recordings relative to their source
enum RecordingSyncStatus: String, Sendable, CaseIterable, Hashable, Comparable {
    case onDeviceOnly = "on_device_only"
    case localOnly = "local_only"
    case synced

    private var sortOrder: Int {
        switch self {
        case .onDeviceOnly: return 0
        case .localOnly: return 1
        case .synced: return 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// A persistent audio import source (device, manual import, etc.)
struct RecordingSource: Identifiable, Sendable, Equatable, Hashable {
    let id: Int64
    var name: String
    var type: RecordingSourceType
    var uniqueIdentifier: String?
    var autoImportEnabled: Bool
    var isActive: Bool
    var directory: String
    var deviceModel: String?
    var lastSeenAt: Date?
    var lastSyncedAt: Date?
    var createdAt: Date

    init(
        id: Int64 = 0,
        name: String,
        type: RecordingSourceType,
        uniqueIdentifier: String? = nil,
        autoImportEnabled: Bool = false,
        isActive: Bool = true,
        directory: String,
        deviceModel: String? = nil,
        lastSeenAt: Date? = nil,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.uniqueIdentifier = uniqueIdentifier
        self.autoImportEnabled = autoImportEnabled
        self.isActive = isActive
        self.directory = directory
        self.deviceModel = deviceModel
        self.lastSeenAt = lastSeenAt
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
    }
}

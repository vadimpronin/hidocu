//
//  RecordingSourceDTO.swift
//  HiDocu
//
//  Data Transfer Object for recording_sources table.
//

import Foundation
import GRDB

struct RecordingSourceDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recording_sources"

    var id: Int64?
    var name: String
    var type: String
    var uniqueIdentifier: String?
    var autoImportEnabled: Bool
    var isActive: Bool
    var directory: String
    var deviceModel: String?
    var lastSeenAt: Date?
    var lastSyncedAt: Date?
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let type = Column(CodingKeys.type)
        static let uniqueIdentifier = Column(CodingKeys.uniqueIdentifier)
        static let autoImportEnabled = Column(CodingKeys.autoImportEnabled)
        static let isActive = Column(CodingKeys.isActive)
        static let directory = Column(CodingKeys.directory)
        static let deviceModel = Column(CodingKeys.deviceModel)
        static let lastSeenAt = Column(CodingKeys.lastSeenAt)
        static let lastSyncedAt = Column(CodingKeys.lastSyncedAt)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case uniqueIdentifier = "unique_identifier"
        case autoImportEnabled = "auto_import_enabled"
        case isActive = "is_active"
        case directory
        case deviceModel = "device_model"
        case lastSeenAt = "last_seen_at"
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
    }

    init(from domain: RecordingSource) {
        self.id = domain.id == 0 ? nil : domain.id
        self.name = domain.name
        self.type = domain.type.rawValue
        self.uniqueIdentifier = domain.uniqueIdentifier
        self.autoImportEnabled = domain.autoImportEnabled
        self.isActive = domain.isActive
        self.directory = domain.directory
        self.deviceModel = domain.deviceModel
        self.lastSeenAt = domain.lastSeenAt
        self.lastSyncedAt = domain.lastSyncedAt
        self.createdAt = domain.createdAt
    }

    func toDomain() -> RecordingSource {
        RecordingSource(
            id: id ?? 0,
            name: name,
            type: RecordingSourceType(rawValue: type) ?? .upload,
            uniqueIdentifier: uniqueIdentifier,
            autoImportEnabled: autoImportEnabled,
            isActive: isActive,
            directory: directory,
            deviceModel: deviceModel,
            lastSeenAt: lastSeenAt,
            lastSyncedAt: lastSyncedAt,
            createdAt: createdAt
        )
    }
}

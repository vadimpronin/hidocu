//
//  RecordingV2.swift
//  HiDocu
//
//  Simplified recording model for context management system.
//  Temporary V2 name to coexist with old Recording during migration.
//

import Foundation

struct RecordingV2: Identifiable, Sendable, Equatable, Hashable {
    let id: Int64
    let filename: String
    let filepath: String
    var title: String?
    var fileSizeBytes: Int?
    var durationSeconds: Int?
    var createdAt: Date
    var modifiedAt: Date
    var deviceSerial: String?
    var deviceModel: String?
    var recordingMode: RecordingMode?
    var recordingSourceId: Int64?
    var syncStatus: RecordingSyncStatus

    var displayTitle: String {
        title ?? filename
    }

    var formattedFileSize: String {
        guard let bytes = fileSizeBytes else { return "--" }
        return bytes.formattedFileSize
    }

    init(
        id: Int64 = 0,
        filename: String,
        filepath: String,
        title: String? = nil,
        fileSizeBytes: Int? = nil,
        durationSeconds: Int? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        deviceSerial: String? = nil,
        deviceModel: String? = nil,
        recordingMode: RecordingMode? = nil,
        recordingSourceId: Int64? = nil,
        syncStatus: RecordingSyncStatus = .localOnly
    ) {
        self.id = id
        self.filename = filename
        self.filepath = filepath
        self.title = title
        self.fileSizeBytes = fileSizeBytes
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deviceSerial = deviceSerial
        self.deviceModel = deviceModel
        self.recordingMode = recordingMode
        self.recordingSourceId = recordingSourceId
        self.syncStatus = syncStatus
    }
}

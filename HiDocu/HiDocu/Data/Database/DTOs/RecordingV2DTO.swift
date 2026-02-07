//
//  RecordingV2DTO.swift
//  HiDocu
//
//  Data Transfer Object for recordings_v2 table.
//  Temporary V2 name to coexist with old RecordingDTO during migration.
//

import Foundation
import GRDB

struct RecordingV2DTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recordings"

    var id: Int64?
    var filename: String
    var filepath: String
    var title: String?
    var fileSizeBytes: Int?
    var durationSeconds: Int?
    var createdAt: Date
    var modifiedAt: Date
    var deviceSerial: String?
    var deviceModel: String?
    var recordingMode: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let filename = Column(CodingKeys.filename)
        static let filepath = Column(CodingKeys.filepath)
        static let title = Column(CodingKeys.title)
        static let fileSizeBytes = Column(CodingKeys.fileSizeBytes)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let createdAt = Column(CodingKeys.createdAt)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
        static let deviceSerial = Column(CodingKeys.deviceSerial)
        static let deviceModel = Column(CodingKeys.deviceModel)
        static let recordingMode = Column(CodingKeys.recordingMode)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case filepath
        case title
        case fileSizeBytes = "file_size_bytes"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case deviceSerial = "device_serial"
        case deviceModel = "device_model"
        case recordingMode = "recording_mode"
    }

    init(from domain: RecordingV2) {
        self.id = domain.id == 0 ? nil : domain.id
        self.filename = domain.filename
        self.filepath = domain.filepath
        self.title = domain.title
        self.fileSizeBytes = domain.fileSizeBytes
        self.durationSeconds = domain.durationSeconds
        self.createdAt = domain.createdAt
        self.modifiedAt = domain.modifiedAt
        self.deviceSerial = domain.deviceSerial
        self.deviceModel = domain.deviceModel
        self.recordingMode = domain.recordingMode?.rawValue
    }

    func toDomain() -> RecordingV2 {
        RecordingV2(
            id: id ?? 0,
            filename: filename,
            filepath: filepath,
            title: title,
            fileSizeBytes: fileSizeBytes,
            durationSeconds: durationSeconds,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deviceSerial: deviceSerial,
            deviceModel: deviceModel,
            recordingMode: recordingMode.flatMap { RecordingMode(rawValue: $0) }
        )
    }
}

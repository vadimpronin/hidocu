//
//  RecordingDTO.swift
//  HiDocu
//
//  Data Transfer Object for recordings - maps between database and domain model.
//

import Foundation
import GRDB

/// Database record for recordings table.
/// Handles conversion between SQLite columns and Swift types.
struct RecordingDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "recordings"
    
    var id: Int64?
    var filename: String
    var filepath: String
    var title: String?
    var durationSeconds: Int?
    var fileSizeBytes: Int?
    var createdAt: Date?
    var modifiedAt: Date?
    var deviceSerial: String?
    var deviceModel: String?
    var recordingMode: String?
    var status: String?
    var playbackPositionSeconds: Int
    
    // MARK: - Column Mapping
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let filename = Column(CodingKeys.filename)
        static let filepath = Column(CodingKeys.filepath)
        static let title = Column(CodingKeys.title)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let fileSizeBytes = Column(CodingKeys.fileSizeBytes)
        static let createdAt = Column(CodingKeys.createdAt)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
        static let deviceSerial = Column(CodingKeys.deviceSerial)
        static let deviceModel = Column(CodingKeys.deviceModel)
        static let recordingMode = Column(CodingKeys.recordingMode)
        static let status = Column(CodingKeys.status)
        static let playbackPositionSeconds = Column(CodingKeys.playbackPositionSeconds)
    }
    
    // Map Swift camelCase to SQL snake_case
    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case filepath
        case title
        case durationSeconds = "duration_seconds"
        case fileSizeBytes = "file_size_bytes"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case deviceSerial = "device_serial"
        case deviceModel = "device_model"
        case recordingMode = "recording_mode"
        case status
        case playbackPositionSeconds = "playback_position_seconds"
    }
    
    // MARK: - Domain Conversion
    
    /// Convert from domain model to DTO
    init(from domain: Recording) {
        self.id = domain.id == 0 ? nil : domain.id
        self.filename = domain.filename
        self.filepath = domain.filepath
        self.title = domain.title
        self.durationSeconds = domain.durationSeconds
        self.fileSizeBytes = domain.fileSizeBytes
        self.createdAt = domain.createdAt
        self.modifiedAt = domain.modifiedAt
        self.deviceSerial = domain.deviceSerial
        self.deviceModel = domain.deviceModel
        self.recordingMode = domain.recordingMode?.rawValue
        self.status = domain.status.rawValue
        self.playbackPositionSeconds = domain.playbackPositionSeconds
    }
    
    /// Convert to domain model
    func toDomain() -> Recording {
        Recording(
            id: id ?? 0,
            filename: filename,
            filepath: filepath,
            title: title,
            durationSeconds: durationSeconds,
            fileSizeBytes: fileSizeBytes,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deviceSerial: deviceSerial,
            deviceModel: deviceModel,
            recordingMode: recordingMode.flatMap { RecordingMode(rawValue: $0) },
            status: status.flatMap { RecordingStatus(rawValue: $0) } ?? .new,
            playbackPositionSeconds: playbackPositionSeconds
        )
    }
}

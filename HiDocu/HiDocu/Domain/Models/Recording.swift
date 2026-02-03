//
//  Recording.swift
//  HiDocu
//
//  Domain model representing an audio recording from a HiDock device.
//

import Foundation

/// Recording mode as determined by the HiDock device.
enum RecordingMode: String, Sendable, CaseIterable {
    case call       // Call recording mode
    case room       // Room/ambient recording
    case whisper    // Whisper/voice memo mode
}

/// Status of a recording in the HiDocu workflow.
enum RecordingStatus: String, Sendable, CaseIterable {
    case new            // Exists on device, not yet downloaded
    case downloaded     // Downloaded to local storage
    case transcribed    // Has been transcribed
}

/// Domain model for an audio recording.
/// Maps to the `recordings` database table.
struct Recording: Identifiable, Sendable, Equatable {
    let id: Int64
    let filename: String
    let filepath: String
    var title: String?
    var durationSeconds: Int?
    var fileSizeBytes: Int?
    var createdAt: Date?
    var modifiedAt: Date?
    var deviceSerial: String?
    var deviceModel: String?
    var recordingMode: RecordingMode?
    var status: RecordingStatus
    var playbackPositionSeconds: Int
    
    /// Display title - uses title if available, otherwise filename
    var displayTitle: String {
        title ?? filename
    }
    
    /// Formatted duration string (HH:MM:SS or MM:SS)
    var formattedDuration: String {
        guard let seconds = durationSeconds else { return "--:--" }
        return seconds.formattedDuration
    }
    
    /// Formatted file size (e.g., "12.5 MB")
    var formattedFileSize: String {
        guard let bytes = fileSizeBytes else { return "--" }
        return bytes.formattedFileSize
    }
    
    /// Create a new Recording with sensible defaults
    init(
        id: Int64 = 0,
        filename: String,
        filepath: String,
        title: String? = nil,
        durationSeconds: Int? = nil,
        fileSizeBytes: Int? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        deviceSerial: String? = nil,
        deviceModel: String? = nil,
        recordingMode: RecordingMode? = nil,
        status: RecordingStatus = .new,
        playbackPositionSeconds: Int = 0
    ) {
        self.id = id
        self.filename = filename
        self.filepath = filepath
        self.title = title
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deviceSerial = deviceSerial
        self.deviceModel = deviceModel
        self.recordingMode = recordingMode
        self.status = status
        self.playbackPositionSeconds = playbackPositionSeconds
    }
}

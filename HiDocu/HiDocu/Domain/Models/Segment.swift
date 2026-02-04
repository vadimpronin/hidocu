//
//  Segment.swift
//  HiDocu
//
//  Domain model for a transcription segment (timed text).
//

import Foundation

/// A segment of transcribed text with timing information.
/// Maps to the `segments` database table.
struct Segment: Identifiable, Sendable, Equatable {
    let id: Int64
    let transcriptionId: Int64
    let startTimeMs: Int
    let endTimeMs: Int
    let text: String
    var speakerLabel: String?
    var confidence: Double?
    
    /// Duration of this segment in milliseconds
    var durationMs: Int {
        endTimeMs - startTimeMs
    }
    
    /// Start time formatted as MM:SS.mmm
    var formattedStartTime: String {
        formatTime(startTimeMs)
    }
    
    /// End time formatted as MM:SS.mmm
    var formattedEndTime: String {
        formatTime(endTimeMs)
    }
    
    private func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let millis = ms % 1000
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }
    
    init(
        id: Int64 = 0,
        transcriptionId: Int64,
        startTimeMs: Int,
        endTimeMs: Int,
        text: String,
        speakerLabel: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.transcriptionId = transcriptionId
        self.startTimeMs = startTimeMs
        self.endTimeMs = endTimeMs
        self.text = text
        self.speakerLabel = speakerLabel
        self.confidence = confidence
    }
}

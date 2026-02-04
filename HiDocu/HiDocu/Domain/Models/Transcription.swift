//
//  Transcription.swift
//  HiDocu
//
//  Domain model for transcription results.
//

import Foundation

/// Domain model for a transcription of a recording.
/// Maps to the `transcriptions` database table.
struct Transcription: Identifiable, Sendable, Equatable {
    let id: Int64
    let recordingId: Int64
    var fullText: String?
    var language: String?
    var modelUsed: String?
    var transcribedAt: Date?
    var confidenceScore: Double?
    var title: String?
    var isPrimary: Bool

    /// Segments that make up this transcription
    var segments: [Segment]

    init(
        id: Int64 = 0,
        recordingId: Int64,
        fullText: String? = nil,
        language: String? = nil,
        modelUsed: String? = nil,
        transcribedAt: Date? = nil,
        confidenceScore: Double? = nil,
        title: String? = nil,
        isPrimary: Bool = false,
        segments: [Segment] = []
    ) {
        self.id = id
        self.recordingId = recordingId
        self.fullText = fullText
        self.language = language
        self.modelUsed = modelUsed
        self.transcribedAt = transcribedAt
        self.confidenceScore = confidenceScore
        self.title = title
        self.isPrimary = isPrimary
        self.segments = segments
    }
}

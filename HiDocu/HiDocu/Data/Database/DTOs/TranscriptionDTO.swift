//
//  TranscriptionDTO.swift
//  HiDocu
//
//  Data Transfer Object for transcriptions.
//

import Foundation
import GRDB

/// Database record for transcriptions table.
struct TranscriptionDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "transcriptions"
    
    var id: Int64?
    var recordingId: Int64
    var fullText: String?
    var language: String?
    var modelUsed: String?
    var transcribedAt: Date?
    var confidenceScore: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case recordingId = "recording_id"
        case fullText = "full_text"
        case language
        case modelUsed = "model_used"
        case transcribedAt = "transcribed_at"
        case confidenceScore = "confidence_score"
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let recordingId = Column(CodingKeys.recordingId)
        static let fullText = Column(CodingKeys.fullText)
        static let language = Column(CodingKeys.language)
        static let modelUsed = Column(CodingKeys.modelUsed)
        static let transcribedAt = Column(CodingKeys.transcribedAt)
        static let confidenceScore = Column(CodingKeys.confidenceScore)
    }
    
    // MARK: - Domain Conversion
    
    init(from domain: Transcription) {
        self.id = domain.id == 0 ? nil : domain.id
        self.recordingId = domain.recordingId
        self.fullText = domain.fullText
        self.language = domain.language
        self.modelUsed = domain.modelUsed
        self.transcribedAt = domain.transcribedAt
        self.confidenceScore = domain.confidenceScore
    }
    
    func toDomain(segments: [Segment] = []) -> Transcription {
        Transcription(
            id: id ?? 0,
            recordingId: recordingId,
            fullText: fullText,
            language: language,
            modelUsed: modelUsed,
            transcribedAt: transcribedAt,
            confidenceScore: confidenceScore,
            segments: segments
        )
    }
}

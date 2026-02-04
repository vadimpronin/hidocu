//
//  SegmentDTO.swift
//  HiDocu
//
//  Data Transfer Object for transcription segments.
//

import Foundation
import GRDB

/// Database record for segments table.
struct SegmentDTO: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "segments"
    
    var id: Int64?
    var transcriptionId: Int64
    var startTimeMs: Int
    var endTimeMs: Int
    var text: String
    var speakerLabel: String?
    var confidence: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case transcriptionId = "transcription_id"
        case startTimeMs = "start_time_ms"
        case endTimeMs = "end_time_ms"
        case text
        case speakerLabel = "speaker_label"
        case confidence
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let transcriptionId = Column(CodingKeys.transcriptionId)
        static let startTimeMs = Column(CodingKeys.startTimeMs)
        static let endTimeMs = Column(CodingKeys.endTimeMs)
        static let text = Column(CodingKeys.text)
        static let speakerLabel = Column(CodingKeys.speakerLabel)
        static let confidence = Column(CodingKeys.confidence)
    }
    
    // MARK: - Domain Conversion
    
    init(from domain: Segment) {
        self.id = domain.id == 0 ? nil : domain.id
        self.transcriptionId = domain.transcriptionId
        self.startTimeMs = domain.startTimeMs
        self.endTimeMs = domain.endTimeMs
        self.text = domain.text
        self.speakerLabel = domain.speakerLabel
        self.confidence = domain.confidence
    }
    
    func toDomain() -> Segment {
        Segment(
            id: id ?? 0,
            transcriptionId: transcriptionId,
            startTimeMs: startTimeMs,
            endTimeMs: endTimeMs,
            text: text,
            speakerLabel: speakerLabel,
            confidence: confidence
        )
    }
}

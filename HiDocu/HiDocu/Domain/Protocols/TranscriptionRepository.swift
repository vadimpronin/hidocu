//
//  TranscriptionRepository.swift
//  HiDocu
//
//  Protocol defining transcription data access operations.
//

import Foundation

/// Protocol for transcription data persistence operations.
protocol TranscriptionRepository: Sendable {
    /// Fetch transcription for a recording (1:1 relationship)
    func fetchForRecording(_ recordingId: Int64) async throws -> Transcription?
    
    /// Insert a new transcription with segments
    func insert(_ transcription: Transcription) async throws -> Transcription
    
    /// Update an existing transcription
    func update(_ transcription: Transcription) async throws
    
    /// Delete transcription for a recording
    func deleteForRecording(_ recordingId: Int64) async throws
    
    /// Fetch all segments for a transcription
    func fetchSegments(transcriptionId: Int64) async throws -> [Segment]
    
    /// Insert segments for a transcription
    func insertSegments(_ segments: [Segment], transcriptionId: Int64) async throws
    
    /// Search transcriptions by text content
    func search(query: String) async throws -> [Transcription]
}

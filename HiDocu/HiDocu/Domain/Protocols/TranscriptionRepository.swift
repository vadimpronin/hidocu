//
//  TranscriptionRepository.swift
//  HiDocu
//
//  Protocol defining transcription data access operations.
//

import Foundation

/// Error type for transcription operations.
enum TranscriptionError: Error, LocalizedError {
    case maxVariantsReached
    case notFound

    var errorDescription: String? {
        switch self {
        case .maxVariantsReached:
            return "Maximum of 5 transcription variants per recording reached."
        case .notFound:
            return "Transcription not found."
        }
    }
}

/// Protocol for transcription data persistence operations.
/// Supports 1:N relationship (up to 5 variants per recording).
protocol TranscriptionRepository: Sendable {
    /// Fetch all transcription variants for a recording, primary first
    func fetchForRecording(_ recordingId: Int64) async throws -> [Transcription]

    /// Fetch a single transcription by ID
    func fetchById(_ id: Int64) async throws -> Transcription?

    /// Fetch the primary transcription for a recording
    func fetchPrimary(recordingId: Int64) async throws -> Transcription?

    /// Count variants for a recording
    func countForRecording(_ recordingId: Int64) async throws -> Int

    /// Insert a new transcription with segments
    func insert(_ transcription: Transcription) async throws -> Transcription

    /// Update an existing transcription
    func update(_ transcription: Transcription) async throws

    /// Delete a single transcription variant by ID
    func delete(id: Int64) async throws

    /// Set a transcription as primary (clears others atomically)
    func setPrimary(id: Int64, recordingId: Int64) async throws

    /// Fetch all segments for a transcription
    func fetchSegments(transcriptionId: Int64) async throws -> [Segment]

    /// Insert segments for a transcription
    func insertSegments(_ segments: [Segment], transcriptionId: Int64) async throws

    /// Search transcriptions by text content
    func search(query: String) async throws -> [Transcription]
}

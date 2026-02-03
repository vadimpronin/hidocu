//
//  RecordingRepository.swift
//  HiDocu
//
//  Protocol defining recording data access operations.
//

import Foundation

/// Protocol for recording data persistence operations.
/// Implemented by the Data layer, used by Use Cases.
protocol RecordingRepository: Sendable {
    /// Fetch all recordings, optionally filtered and sorted
    func fetchAll(
        filterStatus: RecordingStatus?,
        sortBy: RecordingSortField,
        ascending: Bool
    ) async throws -> [Recording]
    
    /// Fetch a single recording by ID
    func fetchById(_ id: Int64) async throws -> Recording?
    
    /// Fetch a recording by filename (unique)
    func fetchByFilename(_ filename: String) async throws -> Recording?
    
    /// Insert a new recording, returns the inserted recording with ID
    func insert(_ recording: Recording) async throws -> Recording
    
    /// Update an existing recording
    func update(_ recording: Recording) async throws
    
    /// Delete a recording by ID
    func delete(id: Int64) async throws
    
    /// Update playback position
    func updatePlaybackPosition(id: Int64, seconds: Int) async throws
    
    /// Update recording status
    func updateStatus(id: Int64, status: RecordingStatus) async throws
    
    /// Search recordings by title or filename
    func search(query: String) async throws -> [Recording]
}

/// Fields available for sorting recordings
enum RecordingSortField: String, Sendable {
    case createdAt
    case modifiedAt
    case title
    case filename
    case durationSeconds
    case fileSizeBytes
}

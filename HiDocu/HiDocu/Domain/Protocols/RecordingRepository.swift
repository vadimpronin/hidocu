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
    
    // MARK: - Sync Operations
    
    /// Check if a recording exists with matching filename AND size.
    /// Used during sync to skip already-downloaded files.
    ///
    /// - Parameters:
    ///   - filename: The filename to check
    ///   - sizeBytes: Expected file size in bytes
    /// - Returns: True if a recording exists with both matching filename and size
    func exists(filename: String, sizeBytes: Int) async throws -> Bool
    
    /// Mark a recording as downloaded and update its file path.
    ///
    /// - Parameters:
    ///   - id: Recording ID
    ///   - relativePath: Relative path to the downloaded file
    func markAsDownloaded(id: Int64, relativePath: String) async throws
    
    /// Update a recording's file location.
    /// Used during conflict resolution when renaming existing files.
    ///
    /// - Parameters:
    ///   - id: Recording ID
    ///   - newRelativePath: New relative path
    ///   - newFilename: New filename (for UNIQUE constraint)
    func updateFilePath(id: Int64, newRelativePath: String, newFilename: String) async throws
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


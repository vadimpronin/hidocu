//
//  FileSystemService.swift
//  HiDocu
//
//  Sandbox-compliant file system operations with security-scoped bookmarks.
//

import Foundation

/// Manages file system operations with sandbox compliance.
/// Handles security-scoped bookmarks for user-selected directories.
@Observable
final class FileSystemService {
    
    // MARK: - Properties
    
    /// Default storage directory for recordings
    private(set) var storageDirectory: URL?
    
    /// UserDefaults key for storing the bookmark
    private let bookmarkKey = "com.hidocu.storageDirectoryBookmark"
    
    // MARK: - Initialization
    
    init() {
        // Try to restore saved bookmark
        restoreSavedBookmark()
        
        // If no saved directory, use default
        if storageDirectory == nil {
            storageDirectory = defaultStorageDirectory
        }
        
        AppLogger.fileSystem.info("FileSystemService initialized. Storage: \(self.storageDirectory?.path ?? "none")")
    }
    
    // MARK: - Directory Management
    
    /// Default storage directory in Application Support
    var defaultStorageDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        return appSupport
            .appendingPathComponent("HiDocu", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }
    
    /// Set a user-selected storage directory.
    /// Creates a security-scoped bookmark for sandbox access.
    func setStorageDirectory(_ url: URL) throws {
        // Start accessing the security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw FileSystemError.accessDenied(url.path)
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        // Create bookmark for future access
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        // Save bookmark to UserDefaults
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        
        self.storageDirectory = url
        
        AppLogger.fileSystem.info("Storage directory set to: \(url.path)")
    }
    
    /// Restore the saved bookmark from UserDefaults
    private func restoreSavedBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                // Bookmark is stale, need to regenerate
                AppLogger.fileSystem.warning("Storage bookmark is stale, will regenerate")
                try setStorageDirectory(url)
            } else {
                self.storageDirectory = url
                AppLogger.fileSystem.info("Restored storage directory: \(url.path)")
            }
        } catch {
            AppLogger.fileSystem.error("Failed to restore bookmark: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File Operations
    
    /// Ensure the storage directory exists
    func ensureStorageDirectoryExists() throws {
        guard let dir = storageDirectory else {
            throw FileSystemError.noStorageDirectory
        }
        
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    /// Get the full path for a recording file
    func recordingPath(for filename: String) throws -> URL {
        guard let dir = storageDirectory else {
            throw FileSystemError.noStorageDirectory
        }
        
        try ensureStorageDirectoryExists()
        return dir.appendingPathComponent(filename)
    }
    
    /// Check if a recording file exists
    func recordingExists(filename: String) -> Bool {
        guard let dir = storageDirectory else { return false }
        let path = dir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Get file size in bytes
    func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int ?? 0
    }
    
    /// Delete a recording file
    func deleteRecording(filename: String) throws {
        guard let dir = storageDirectory else {
            throw FileSystemError.noStorageDirectory
        }
        
        let path = dir.appendingPathComponent(filename)
        try FileManager.default.removeItem(at: path)
        
        AppLogger.fileSystem.info("Deleted: \(filename)")
    }
    
    /// List all recording files in storage
    func listRecordings() throws -> [URL] {
        guard let dir = storageDirectory else {
            throw FileSystemError.noStorageDirectory
        }
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        // Filter for audio files
        let audioExtensions = ["hda", "mp3", "m4a", "wav"]
        return contents.filter { url in
            audioExtensions.contains(url.pathExtension.lowercased())
        }
    }
    
    /// Access a security-scoped resource for operations
    func withSecurityScopedAccess<T>(to url: URL, _ operation: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}

// MARK: - Errors

enum FileSystemError: LocalizedError {
    case noStorageDirectory
    case accessDenied(String)
    case fileNotFound(String)
    case deleteFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noStorageDirectory:
            return "No storage directory configured"
        case .accessDenied(let path):
            return "Access denied to: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .deleteFailed(let reason):
            return "Delete failed: \(reason)"
        }
    }
}

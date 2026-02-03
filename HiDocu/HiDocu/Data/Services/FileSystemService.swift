//
//  FileSystemService.swift
//  HiDocu
//
//  Sandbox-compliant file system operations with security-scoped bookmarks.
//

import Foundation

/// Manages file system operations with sandbox compliance.
/// Handles security-scoped bookmarks for user-selected directories.
///
/// - Important: All file operations on user-selected directories MUST use
///   `withSecurityScopedAccess` to properly manage sandbox access.
@Observable
final class FileSystemService {
    
    // MARK: - Properties
    
    /// The resolved storage directory URL (may require security scope access)
    private(set) var storageDirectory: URL?
    
    /// Whether the storage directory requires security-scoped access
    private var requiresSecurityScope: Bool = false
    
    /// UserDefaults key for storing the bookmark
    private let bookmarkKey = "com.hidocu.storageDirectoryBookmark"
    
    // MARK: - Initialization
    
    init() {
        // Try to restore saved bookmark
        restoreSavedBookmark()
        
        // If no saved directory, use default (doesn't require security scope)
        if storageDirectory == nil {
            storageDirectory = defaultStorageDirectory
            requiresSecurityScope = false
        }
        
        AppLogger.fileSystem.info("FileSystemService initialized. Storage: \(self.storageDirectory?.path ?? "none")")
    }
    
    // MARK: - Directory Management
    
    /// Default storage directory in Application Support (no security scope needed)
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
        self.requiresSecurityScope = true
        
        AppLogger.fileSystem.info("Storage directory set to: \(url.path)")
    }
    
    /// Reset to default storage directory
    func resetToDefaultDirectory() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        storageDirectory = defaultStorageDirectory
        requiresSecurityScope = false
        AppLogger.fileSystem.info("Reset to default storage directory")
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
                AppLogger.fileSystem.warning("Storage bookmark is stale, attempting to regenerate")
                // Try to start access to regenerate bookmark
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    try setStorageDirectory(url)
                } else {
                    AppLogger.fileSystem.error("Cannot access stale bookmark, falling back to default")
                    storageDirectory = defaultStorageDirectory
                    requiresSecurityScope = false
                }
            } else {
                self.storageDirectory = url
                self.requiresSecurityScope = true
                AppLogger.fileSystem.info("Restored storage directory: \(url.path)")
            }
        } catch {
            AppLogger.fileSystem.error("Failed to restore bookmark: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Security Scoped Access
    
    /// Execute an operation with proper security-scoped access.
    /// This is required for ALL file operations on user-selected directories.
    func withSecurityScopedAccess<T>(to url: URL, _ operation: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
    
    /// Execute an operation on the storage directory with proper access.
    private func withStorageAccess<T>(_ operation: (URL) throws -> T) throws -> T {
        guard let dir = storageDirectory else {
            throw FileSystemError.noStorageDirectory
        }
        
        if requiresSecurityScope {
            return try withSecurityScopedAccess(to: dir) {
                try operation(dir)
            }
        } else {
            return try operation(dir)
        }
    }
    
    // MARK: - File Operations
    
    /// Ensure the storage directory exists
    func ensureStorageDirectoryExists() throws {
        try withStorageAccess { dir in
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
    
    /// Get the full path for a recording file
    func recordingPath(for filename: String) throws -> URL {
        try withStorageAccess { dir in
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return dir.appendingPathComponent(filename)
        }
    }
    
    /// Check if a recording file exists
    func recordingExists(filename: String) -> Bool {
        guard let dir = storageDirectory else { return false }
        
        do {
            return try withStorageAccess { _ in
                let path = dir.appendingPathComponent(filename)
                return FileManager.default.fileExists(atPath: path.path)
            }
        } catch {
            return false
        }
    }
    
    /// Get file size in bytes
    func fileSize(at url: URL) throws -> Int {
        if requiresSecurityScope {
            return try withSecurityScopedAccess(to: url) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                return attributes[.size] as? Int ?? 0
            }
        } else {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int ?? 0
        }
    }
    
    /// Delete a recording file
    func deleteRecording(filename: String) throws {
        try withStorageAccess { dir in
            let path = dir.appendingPathComponent(filename)
            try FileManager.default.removeItem(at: path)
            AppLogger.fileSystem.info("Deleted: \(filename)")
        }
    }
    
    /// List all recording files in storage
    func listRecordings() throws -> [URL] {
        try withStorageAccess { dir in
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

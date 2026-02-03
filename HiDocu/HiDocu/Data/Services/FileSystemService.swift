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
    
    // MARK: - Relative Path Handling
    
    /// Resolve a relative path to an absolute URL.
    /// Used when reading from database (which stores relative paths).
    ///
    /// - Parameter relativePath: Path relative to storage directory
    /// - Returns: Absolute URL combining storage directory and relative path
    /// - Throws: FileSystemError.noStorageDirectory if storage not configured
    func resolve(relativePath: String) throws -> URL {
        guard let dir = storageDirectory else {
            throw FileSystemError.noStorageDirectory
        }
        return dir.appendingPathComponent(relativePath)
    }
    
    /// Get the relative path by stripping the storage directory prefix.
    /// Used when writing to database (to store relative paths).
    ///
    /// - Parameter absoluteURL: An absolute file URL
    /// - Returns: Relative path string, or nil if URL is not within storage directory
    func relativePath(for absoluteURL: URL) -> String? {
        guard let dir = storageDirectory else { return nil }
        
        let storagePath = dir.standardizedFileURL.path
        let filePath = absoluteURL.standardizedFileURL.path
        
        // Check if file is within storage directory
        guard filePath.hasPrefix(storagePath) else { return nil }
        
        // Strip the storage directory prefix and leading slash
        var relative = String(filePath.dropFirst(storagePath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return relative
    }
    
    // MARK: - File Movement & Renaming
    
    /// Atomically rename a file.
    /// Used during conflict resolution when a new version of a file arrives from device.
    ///
    /// - Parameters:
    ///   - sourceURL: Current file URL
    ///   - newFilename: New filename (same directory)
    /// - Returns: URL with new filename
    /// - Throws: FileSystemError if rename fails
    func renameFile(at sourceURL: URL, to newFilename: String) throws -> URL {
        let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newFilename)
        
        let operation = {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
        
        if requiresSecurityScope, let dir = storageDirectory {
            try withSecurityScopedAccess(to: dir, operation)
        } else {
            try operation()
        }
        
        AppLogger.fileSystem.info("Renamed \(sourceURL.lastPathComponent) to \(newFilename)")
        return destinationURL
    }
    
    /// Move a file from a temporary location into the storage directory.
    ///
    /// - Parameters:
    ///   - sourceURL: Source file URL (typically in temp directory)
    ///   - filename: Target filename within storage directory
    /// - Returns: Final URL of the moved file
    /// - Throws: FileSystemError if move fails
    func moveToStorage(from sourceURL: URL, filename: String) throws -> URL {
        let destinationURL = try recordingPath(for: filename)
        
        let operation = {
            // Remove existing file if present (shouldn't happen with our flow, but safety first)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
        
        if requiresSecurityScope, let dir = storageDirectory {
            try withSecurityScopedAccess(to: dir, operation)
        } else {
            try operation()
        }
        
        AppLogger.fileSystem.info("Moved \(sourceURL.lastPathComponent) to storage as \(filename)")
        return destinationURL
    }
    
    /// Copy a file into the storage directory.
    /// Used for manual import when we can't move (e.g., from external volumes).
    ///
    /// - Parameters:
    ///   - sourceURL: Source file URL
    ///   - filename: Target filename within storage directory
    /// - Returns: Final URL of the copied file
    /// - Throws: FileSystemError if copy fails
    func copyToStorage(from sourceURL: URL, filename: String) throws -> URL {
        let destinationURL = try recordingPath(for: filename)
        
        let operation = {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
        
        if requiresSecurityScope, let dir = storageDirectory {
            try withSecurityScopedAccess(to: dir, operation)
        } else {
            try operation()
        }
        
        AppLogger.fileSystem.info("Copied \(sourceURL.lastPathComponent) to storage as \(filename)")
        return destinationURL
    }
    
    // MARK: - Async Wrappers
    
    /// Execute an async operation with proper storage directory access.
    /// Runs on a background thread to avoid blocking UI.
    ///
    /// - Parameter operation: Closure receiving the storage directory URL
    /// - Returns: Result of the operation
    /// - Throws: FileSystemError or operation errors
    func withStorageAccessAsync<T: Sendable>(_ operation: @Sendable @escaping (URL) throws -> T) async throws -> T {
        guard let dir = storageDirectory else {
            throw FileSystemError.noStorageDirectory
        }
        
        let requiresScope = self.requiresSecurityScope
        
        return try await Task.detached {
            if requiresScope {
                let accessed = dir.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        dir.stopAccessingSecurityScopedResource()
                    }
                }
                return try operation(dir)
            } else {
                return try operation(dir)
            }
        }.value
    }
    
    /// Generate a unique backup filename for conflict resolution.
    /// Example: "Recording.hda" -> "Recording_backup_1.hda"
    ///
    /// - Parameter filename: Original filename
    /// - Returns: Backup filename that doesn't exist in storage
    func generateBackupFilename(for filename: String) throws -> String {
        let url = URL(fileURLWithPath: filename)
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        var counter = 1
        var backupName: String
        
        repeat {
            backupName = "\(name)_backup_\(counter).\(ext)"
            counter += 1
        } while recordingExists(filename: backupName)
        
        return backupName
    }
}

// MARK: - Errors

enum FileSystemError: LocalizedError {
    case noStorageDirectory
    case accessDenied(String)
    case fileNotFound(String)
    case deleteFailed(String)
    case renameFailed(String)
    case moveFailed(String)
    case copyFailed(String)
    
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
        case .renameFailed(let reason):
            return "Rename failed: \(reason)"
        case .moveFailed(let reason):
            return "Move failed: \(reason)"
        case .copyFailed(let reason):
            return "Copy failed: \(reason)"
        }
    }
}

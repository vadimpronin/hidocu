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

    /// Execute an async operation with proper security-scoped access.
    func withSecurityScopedAccess<T>(to url: URL, _ operation: () async throws -> T) async throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
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

    // MARK: - Data Directory (Context Management)

    /// Relative path for uncategorized documents
    static let uncategorizedPath = "Uncategorized"

    /// The data directory for documents (default: ~/HiDocu)
    var dataDirectory: URL {
        if let custom = customDataDirectory {
            return custom
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("HiDocu", isDirectory: true)
    }

    /// Custom data directory override (set via settings)
    private(set) var customDataDirectory: URL?

    /// Set a custom data directory
    func setDataDirectory(_ url: URL) {
        customDataDirectory = url
        AppLogger.fileSystem.info("Data directory set to: \(url.path)")
    }

    /// Reset data directory to default ~/HiDocu
    func resetDataDirectory() {
        customDataDirectory = nil
        AppLogger.fileSystem.info("Data directory reset to default")
    }

    /// Trash directory for deleted documents
    var trashDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("HiDocu", isDirectory: true)
            .appendingPathComponent("trash", isDirectory: true)
    }

    /// Create a document folder on disk
    /// Returns the relative disk path (e.g., "42.document")
    func createDocumentFolder(documentId: Int64) throws -> String {
        let folderName = "\(documentId).document"
        let folderURL = dataDirectory.appendingPathComponent(folderName, isDirectory: true)

        let fm = FileManager.default
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: folderURL.appendingPathComponent("sources", isDirectory: true),
            withIntermediateDirectories: true
        )

        // Create empty body.md and summary.md
        let bodyURL = folderURL.appendingPathComponent("body.md")
        let summaryURL = folderURL.appendingPathComponent("summary.md")
        if !fm.fileExists(atPath: bodyURL.path) {
            fm.createFile(atPath: bodyURL.path, contents: nil)
        }
        if !fm.fileExists(atPath: summaryURL.path) {
            fm.createFile(atPath: summaryURL.path, contents: nil)
        }

        // Create metadata.yaml
        let metadataURL = folderURL.appendingPathComponent("metadata.yaml")
        if !fm.fileExists(atPath: metadataURL.path) {
            let yaml = "title: \"Untitled\"\ncreated: \(ISO8601DateFormatter().string(from: Date()))\n"
            try yaml.write(to: metadataURL, atomically: true, encoding: .utf8)
        }

        AppLogger.fileSystem.info("Created document folder: \(folderName)")
        return folderName
    }

    /// Create a source folder inside a document's sources directory
    /// Returns the relative disk path (e.g., "42.document/sources/7.source")
    func createSourceFolder(documentDiskPath: String, sourceId: Int64) throws -> String {
        let sourceFolderName = "\(sourceId).source"
        let sourcesDir = dataDirectory
            .appendingPathComponent(documentDiskPath, isDirectory: true)
            .appendingPathComponent("sources", isDirectory: true)
        let sourceFolder = sourcesDir.appendingPathComponent(sourceFolderName, isDirectory: true)

        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)

        let relativePath = "\(documentDiskPath)/sources/\(sourceFolderName)"
        AppLogger.fileSystem.info("Created source folder: \(relativePath)")
        return relativePath
    }

    /// Read document body from disk
    func readDocumentBody(diskPath: String) throws -> String {
        let bodyURL = dataDirectory
            .appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("body.md")
        guard FileManager.default.fileExists(atPath: bodyURL.path) else {
            return ""
        }
        return try String(contentsOf: bodyURL, encoding: .utf8)
    }

    /// Read document summary from disk
    func readDocumentSummary(diskPath: String) throws -> String {
        let summaryURL = dataDirectory
            .appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("summary.md")
        guard FileManager.default.fileExists(atPath: summaryURL.path) else {
            return ""
        }
        return try String(contentsOf: summaryURL, encoding: .utf8)
    }

    /// Write document body to disk
    func writeDocumentBody(diskPath: String, content: String) throws {
        let bodyURL = dataDirectory
            .appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("body.md")
        try content.write(to: bodyURL, atomically: true, encoding: .utf8)
    }

    /// Write document summary to disk
    func writeDocumentSummary(diskPath: String, content: String) throws {
        let summaryURL = dataDirectory
            .appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("summary.md")
        try content.write(to: summaryURL, atomically: true, encoding: .utf8)
    }

    /// Move a document folder to the trash directory
    /// Returns the trash path
    func moveDocumentToTrash(diskPath: String, documentId: Int64) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: trashDirectory, withIntermediateDirectories: true)

        let sourceURL = dataDirectory.appendingPathComponent(diskPath, isDirectory: true)
        let trashName = "\(documentId)_\(Int(Date().timeIntervalSince1970)).document"
        let trashURL = trashDirectory.appendingPathComponent(trashName, isDirectory: true)

        if fm.fileExists(atPath: sourceURL.path) {
            try fm.moveItem(at: sourceURL, to: trashURL)
        }

        AppLogger.fileSystem.info("Moved document to trash: \(trashName)")
        return trashName
    }

    /// Restore a document from trash back to data directory
    func restoreDocumentFromTrash(trashPath: String, targetPath: String) throws {
        let trashURL = trashDirectory.appendingPathComponent(trashPath, isDirectory: true)
        let targetURL = dataDirectory.appendingPathComponent(targetPath, isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: trashURL.path) {
            try fm.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fm.moveItem(at: trashURL, to: targetURL)
        }

        AppLogger.fileSystem.info("Restored document from trash: \(trashPath) -> \(targetPath)")
    }

    /// Remove expired trash entries from disk
    func cleanupExpiredTrash(trashPaths: [String]) {
        let fm = FileManager.default
        for path in trashPaths {
            let url = trashDirectory.appendingPathComponent(path, isDirectory: true)
            try? fm.removeItem(at: url)
        }
    }

    /// Remove a specific trash entry from disk
    func permanentlyDeleteTrash(trashPath: String) {
        let url = trashDirectory.appendingPathComponent(trashPath, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }

    /// Remove a source folder from disk
    func removeSourceFolder(diskPath: String) {
        let url = dataDirectory.appendingPathComponent(diskPath, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }

    /// Ensure the data directory exists
    func ensureDataDirectoryExists() throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    /// Ensure the Uncategorized directory exists
    func ensureUncategorizedDirectoryExists() throws {
        let uncategorizedURL = dataDirectory.appendingPathComponent(Self.uncategorizedPath, isDirectory: true)
        try FileManager.default.createDirectory(at: uncategorizedURL, withIntermediateDirectories: true)
        AppLogger.fileSystem.info("Ensured Uncategorized directory exists")
    }

    // MARK: - Audio File Management

    /// Move audio file to Recordings/YYYY/MM/ directory structure.
    /// Returns relative path (e.g., "Recordings/2026/02/file.hda").
    /// If file exists at destination, removes it first (dedup prevents duplicates upstream).
    ///
    /// - Parameters:
    ///   - sourceURL: Source file URL (temporary location)
    ///   - filename: Target filename
    ///   - date: Recording date (used for year/month subdirectories)
    /// - Returns: Relative path from data directory
    /// - Throws: FileSystemError on failure
    func moveAudioToRecordings(from sourceURL: URL, filename: String, date: Date) throws -> String {
        return try performAudioOperation(
            from: sourceURL,
            filename: filename,
            date: date,
            isMove: true
        )
    }

    /// Copy audio file to Recordings/YYYY/MM/ directory structure.
    /// Returns relative path (e.g., "Recordings/2026/02/file.hda").
    /// Used for manual import to preserve user's original file.
    ///
    /// - Parameters:
    ///   - sourceURL: Source file URL
    ///   - filename: Target filename
    ///   - date: Recording date (used for year/month subdirectories)
    /// - Returns: Relative path from data directory
    /// - Throws: FileSystemError on failure
    func copyAudioToRecordings(from sourceURL: URL, filename: String, date: Date) throws -> String {
        return try performAudioOperation(
            from: sourceURL,
            filename: filename,
            date: date,
            isMove: false
        )
    }

    /// Private helper for audio move/copy operations to avoid duplication.
    private func performAudioOperation(
        from sourceURL: URL,
        filename: String,
        date: Date,
        isMove: Bool
    ) throws -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let monthString = String(format: "%02d", month)

        // Build relative path: Recordings/YYYY/MM/filename
        let relativePath = "Recordings/\(year)/\(monthString)/\(filename)"
        let destinationURL = dataDirectory.appendingPathComponent(relativePath)

        // Create intermediate directories
        let parentURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        // Remove existing file if present (dedup prevents duplicates upstream)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
            AppLogger.fileSystem.info("Removed existing file at destination: \(relativePath)")
        }

        // Move or copy the file
        if isMove {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            AppLogger.fileSystem.info("Moved audio to: \(relativePath)")
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            AppLogger.fileSystem.info("Copied audio to: \(relativePath)")
        }

        return relativePath
    }

    /// Read the `audio_path` value from a source's `source.yaml` metadata file.
    ///
    /// - Parameter sourceDiskPath: Relative path to source folder (e.g., "42.document/sources/7.source")
    /// - Returns: The relative audio path (e.g., "Recordings/2026/01/file.hda"), or nil if not found.
    func readSourceAudioPath(sourceDiskPath: String) -> String? {
        let yamlURL = dataDirectory
            .appendingPathComponent(sourceDiskPath, isDirectory: true)
            .appendingPathComponent("source.yaml")
        guard let content = try? String(contentsOf: yamlURL, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("audio_path:") {
                var value = String(trimmed.dropFirst("audio_path:".count))
                    .trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes if present
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Write source.yaml metadata file inside a source folder.
    ///
    /// - Parameters:
    ///   - sourceDiskPath: Relative path to source folder (e.g., "42.document/sources/7.source")
    ///   - audioRelativePath: Relative path to audio file (e.g., "Recordings/2026/02/file.hda")
    ///   - originalFilename: Original filename from device
    ///   - durationSeconds: Recording duration in seconds (optional)
    ///   - fileSizeBytes: File size in bytes (optional)
    ///   - deviceSerial: Device serial number (optional)
    ///   - deviceModel: Device model string (optional)
    ///   - recordingMode: Recording mode (optional)
    ///   - recordedAt: Recording timestamp (optional)
    /// - Throws: Error if write fails
    func writeSourceYAML(
        sourceDiskPath: String,
        audioRelativePath: String,
        originalFilename: String,
        durationSeconds: Int?,
        fileSizeBytes: Int?,
        deviceSerial: String?,
        deviceModel: String?,
        recordingMode: String?,
        recordedAt: Date?
    ) throws {
        let sourceURL = dataDirectory.appendingPathComponent(sourceDiskPath, isDirectory: true)
        let yamlURL = sourceURL.appendingPathComponent("source.yaml")

        var lines: [String] = []
        lines.append("type: recording")
        lines.append("audio_path: \(yamlQuoted(audioRelativePath))")
        lines.append("original_filename: \(yamlQuoted(originalFilename))")

        if let duration = durationSeconds {
            lines.append("duration_seconds: \(duration)")
        }
        if let size = fileSizeBytes {
            lines.append("file_size_bytes: \(size)")
        }
        if let serial = deviceSerial {
            lines.append("device_serial: \(yamlQuoted(serial))")
        }
        if let model = deviceModel {
            lines.append("device_model: \(yamlQuoted(model))")
        }
        if let mode = recordingMode {
            lines.append("recording_mode: \(yamlQuoted(mode))")
        }
        if let recorded = recordedAt {
            lines.append("recorded_at: \(Self.isoFormatter.string(from: recorded))")
        }

        // Always include import timestamp
        lines.append("imported_at: \(Self.isoFormatter.string(from: Date()))")

        let yaml = lines.joined(separator: "\n") + "\n"
        try yaml.write(to: yamlURL, atomically: true, encoding: .utf8)

        AppLogger.fileSystem.info("Wrote source.yaml: \(sourceDiskPath)/source.yaml")
    }

    /// Write a transcript .md file to a source folder
    func writeTranscriptFile(sourceDiskPath: String, filename: String, content: String) throws -> String {
        let sourceURL = dataDirectory.appendingPathComponent(sourceDiskPath, isDirectory: true)
        let fileURL = sourceURL.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return "\(sourceDiskPath)/\(filename)"
    }

    /// Read a transcript .md file from disk
    func readTranscriptFile(path: String) throws -> String {
        let fileURL = dataDirectory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return "" }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    /// Update metadata.yaml title in a document folder
    @available(*, deprecated, message: "Use writeDocumentMetadata(_:) instead")
    func updateDocumentMetadata(diskPath: String, title: String) throws {
        let metadataURL = dataDirectory
            .appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("metadata.yaml")
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let yaml = "title: \"\(escapedTitle)\"\ncreated: \(ISO8601DateFormatter().string(from: Date()))\n"
        try yaml.write(to: metadataURL, atomically: true, encoding: .utf8)
    }

    /// Update metadata.yaml with document id for identity across renames.
    @available(*, deprecated, message: "Use writeDocumentMetadata(_:) instead")
    func updateDocumentMetadata(diskPath: String, title: String, documentId: Int64) throws {
        let metadataURL = dataDirectory
            .appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("metadata.yaml")
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let yaml = "id: \(documentId)\ntitle: \"\(escapedTitle)\"\ncreated: \(ISO8601DateFormatter().string(from: Date()))\n"
        try yaml.write(to: metadataURL, atomically: true, encoding: .utf8)
    }

    // MARK: - YAML Metadata Persistence

    /// Write complete document metadata.yaml from a Document domain model.
    func writeDocumentMetadata(_ document: Document) throws {
        let metadataURL = dataDirectory
            .appendingPathComponent(document.diskPath, isDirectory: true)
            .appendingPathComponent("metadata.yaml")
        let yaml = documentMetadataYAML(document)
        try yaml.write(to: metadataURL, atomically: true, encoding: .utf8)
    }

    /// Write folder metadata.yaml from a Folder domain model.
    func writeFolderMetadata(_ folder: Folder) throws {
        guard let diskPath = folder.diskPath, !diskPath.isEmpty else { return }
        let metadataURL = dataDirectory
            .appendingPathComponent(diskPath, isDirectory: true)
            .appendingPathComponent("metadata.yaml")
        let yaml = folderMetadataYAML(folder)
        try yaml.write(to: metadataURL, atomically: true, encoding: .utf8)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    private func documentMetadataYAML(_ doc: Document) -> String {
        var lines: [String] = []
        lines.append("id: \(doc.id)")
        lines.append("title: \(yamlQuoted(doc.title))")
        lines.append("document_type: \(doc.documentType)")
        lines.append("sort_order: \(doc.sortOrder)")
        lines.append("prefer_summary: \(doc.preferSummary)")
        lines.append("minimize_before_llm: \(doc.minimizeBeforeLLM)")
        lines.append("created_at: \(Self.isoFormatter.string(from: doc.createdAt))")
        lines.append("modified_at: \(Self.isoFormatter.string(from: doc.modifiedAt))")
        if let summaryGeneratedAt = doc.summaryGeneratedAt {
            lines.append("summary_generated_at: \(Self.isoFormatter.string(from: summaryGeneratedAt))")
        }
        if let summaryModel = doc.summaryModel {
            lines.append("summary_model: \(yamlQuoted(summaryModel))")
        }
        if doc.summaryGeneratedAt != nil {
            lines.append("summary_edited: \(doc.summaryEdited)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func folderMetadataYAML(_ folder: Folder) -> String {
        var lines: [String] = []
        lines.append("id: \(folder.id)")
        lines.append("name: \(yamlQuoted(folder.name))")
        lines.append("sort_order: \(folder.sortOrder)")
        lines.append("prefer_summary: \(folder.preferSummary)")
        lines.append("minimize_before_llm: \(folder.minimizeBeforeLLM)")
        if let tc = folder.transcriptionContext, !tc.isEmpty {
            lines.append("transcription_context: \(yamlQuoted(tc))")
        }
        if let cc = folder.categorizationContext, !cc.isEmpty {
            lines.append("categorization_context: \(yamlQuoted(cc))")
        }
        lines.append("created_at: \(Self.isoFormatter.string(from: folder.createdAt))")
        lines.append("modified_at: \(Self.isoFormatter.string(from: folder.modifiedAt))")
        return lines.joined(separator: "\n") + "\n"
    }

    private func yamlQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - Hierarchical File System

    /// Create a physical directory for a folder within the data directory.
    /// Creates intermediate directories as needed.
    func ensureFolderDirectoryExists(relativePath: String) throws {
        guard !relativePath.isEmpty else { return }
        let url = dataDirectory.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Move a directory from one relative path to another within the data directory.
    /// Creates parent directories at the destination as needed.
    func moveDirectory(from oldRelativePath: String, to newRelativePath: String) throws {
        let source = dataDirectory.appendingPathComponent(oldRelativePath, isDirectory: true)
        let destination = dataDirectory.appendingPathComponent(newRelativePath, isDirectory: true)
        let fm = FileManager.default
        // Ensure parent of destination exists
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.moveItem(at: source, to: destination)
    }

    /// Check if a relative path exists as a directory within the data directory.
    func directoryExists(relativePath: String) -> Bool {
        var isDir: ObjCBool = false
        let url = dataDirectory.appendingPathComponent(relativePath, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Create a document bundle folder using a human-readable title within the given parent directory.
    /// Returns the relative disk path (e.g., "Project X/Meeting Notes.document").
    func createDocumentFolder(title: String, parentRelativePath: String) throws -> String {
        let sanitizedTitle = PathSanitizer.sanitize(title)
        let docDirName = PathSanitizer.resolveConflict(
            baseName: sanitizedTitle,
            suffix: ".document"
        ) { candidate in
            let fullRelative = parentRelativePath.isEmpty
                ? candidate
                : "\(parentRelativePath)/\(candidate)"
            return directoryExists(relativePath: fullRelative)
        }

        let diskPath = parentRelativePath.isEmpty
            ? docDirName
            : "\(parentRelativePath)/\(docDirName)"

        let folderURL = dataDirectory.appendingPathComponent(diskPath, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: folderURL.appendingPathComponent("sources", isDirectory: true),
            withIntermediateDirectories: true
        )

        // Create empty body.md and summary.md
        let bodyURL = folderURL.appendingPathComponent("body.md")
        let summaryURL = folderURL.appendingPathComponent("summary.md")
        if !fm.fileExists(atPath: bodyURL.path) {
            fm.createFile(atPath: bodyURL.path, contents: nil)
        }
        if !fm.fileExists(atPath: summaryURL.path) {
            fm.createFile(atPath: summaryURL.path, contents: nil)
        }

        // Create metadata.yaml placeholder
        let metadataURL = folderURL.appendingPathComponent("metadata.yaml")
        if !fm.fileExists(atPath: metadataURL.path) {
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let yaml = "title: \"\(escapedTitle)\"\ncreated: \(ISO8601DateFormatter().string(from: Date()))\n"
            try yaml.write(to: metadataURL, atomically: true, encoding: .utf8)
        }

        AppLogger.fileSystem.info("Created document folder: \(diskPath)")
        return diskPath
    }

    /// Rename a document's .document bundle on disk.
    /// Returns the new relative disk path.
    func renameDocumentFolder(oldDiskPath: String, newTitle: String) throws -> String {
        let sanitizedTitle = PathSanitizer.sanitize(newTitle)
        let parentDir = (oldDiskPath as NSString).deletingLastPathComponent

        let newDocDirName = PathSanitizer.resolveConflict(
            baseName: sanitizedTitle,
            suffix: ".document"
        ) { candidate in
            let fullRelative = parentDir.isEmpty ? candidate : "\(parentDir)/\(candidate)"
            // Don't conflict with self
            if fullRelative == oldDiskPath { return false }
            return directoryExists(relativePath: fullRelative)
        }

        let newDiskPath = parentDir.isEmpty
            ? newDocDirName
            : "\(parentDir)/\(newDocDirName)"

        if newDiskPath != oldDiskPath {
            try moveDirectory(from: oldDiskPath, to: newDiskPath)
        }

        return newDiskPath
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

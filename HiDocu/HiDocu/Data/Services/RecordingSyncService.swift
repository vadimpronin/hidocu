//
//  RecordingSyncService.swift
//  HiDocu
//
//  Core synchronization engine for downloading recordings from HiDock devices.
//  Handles conflict resolution, progress tracking, and file validation.
//

import Foundation

/// Narrow protocol covering only what the sync service needs from a device.
/// `DeviceConnectionService` is `@Observable` (not `Sendable`), so it cannot
/// conform to `DeviceRepository`. This protocol avoids that constraint.
protocol DeviceFileProvider {
    var connectionInfo: DeviceConnectionInfo? { get }
    func listFiles() async throws -> [DeviceFileInfo]
    func downloadFile(filename: String, toPath: URL, progress: @escaping (Double) -> Void) async throws
}

/// Statistics from a sync operation
struct SyncStats: Sendable {
    let total: Int
    let downloaded: Int
    let skipped: Int
    let failed: Int
    
    var description: String {
        "Total: \(total), Downloaded: \(downloaded), Skipped: \(skipped), Failed: \(failed)"
    }
}

/// Observable service for synchronizing recordings from HiDock device to local storage.
///
/// The sync algorithm handles:
/// 1. Skip files that already exist with matching size
/// 2. Conflict resolution for same filename but different content
/// 3. Download to temp, validate, then move to storage
/// 4. Proper metadata extraction from device
///
/// - Important: The UNIQUE constraint on `filename` in the database dictates that
///   conflict resolution (rename existing file) must happen BEFORE inserting new file.
@Observable
final class RecordingSyncService {
    
    // MARK: - Observable State (for UI)
    
    /// Whether a sync operation is currently in progress
    private(set) var isSyncing: Bool = false
    
    /// Current progress (0.0 - 1.0) across all files
    private(set) var progress: Double = 0.0
    
    /// Currently processing file name
    private(set) var currentFile: String?
    
    /// Error message if sync failed
    private(set) var errorMessage: String?
    
    /// Statistics from the last sync operation
    private(set) var syncStats: SyncStats?
    
    // MARK: - Dependencies
    
    private let deviceService: any DeviceFileProvider
    private let fileSystemService: FileSystemService
    private let audioService: AudioCompatibilityService
    private let repository: any RecordingRepository

    // MARK: - Initialization

    init(
        deviceService: any DeviceFileProvider,
        fileSystemService: FileSystemService,
        audioService: AudioCompatibilityService,
        repository: any RecordingRepository
    ) {
        self.deviceService = deviceService
        self.fileSystemService = fileSystemService
        self.audioService = audioService
        self.repository = repository
        
        AppLogger.fileSystem.info("RecordingSyncService initialized")
    }
    
    // MARK: - Sync from Device
    
    /// Synchronize recordings from the connected HiDock device.
    ///
    /// Algorithm:
    /// 1. Get file list from device
    /// 2. For each file:
    ///    - Skip if exists with matching size
    ///    - Handle conflict if exists with different size (rename existing)
    ///    - Download to temp, validate, move to storage, insert into DB
    func syncFromDevice() async {
        guard !isSyncing else {
            AppLogger.fileSystem.warning("Sync already in progress")
            return
        }
        
        await MainActor.run {
            isSyncing = true
            progress = 0.0
            currentFile = nil
            errorMessage = nil
            syncStats = nil
        }
        
        var downloaded = 0
        var skipped = 0
        var failed = 0
        
        do {
            // Ensure storage directory exists
            try fileSystemService.ensureStorageDirectoryExists()
            
            // Get file list from device
            let deviceFiles = try await deviceService.listFiles()
            let total = deviceFiles.count
            
            AppLogger.fileSystem.info("Starting sync: \(total) files on device")
            
            for (index, fileInfo) in deviceFiles.enumerated() {
                // Check for cancellation
                try Task.checkCancellation()
                
                await MainActor.run {
                    currentFile = fileInfo.filename
                    progress = Double(index) / Double(max(total, 1))
                }
                
                do {
                    let result = try await processFile(fileInfo)
                    switch result {
                    case .downloaded:
                        downloaded += 1
                    case .skipped:
                        skipped += 1
                    }
                } catch {
                    AppLogger.fileSystem.error("Failed to sync \(fileInfo.filename): \(error.localizedDescription)")
                    failed += 1
                }
            }
            
            let stats = SyncStats(total: total, downloaded: downloaded, skipped: skipped, failed: failed)
            await MainActor.run {
                syncStats = stats
                progress = 1.0
                currentFile = nil
            }
            
            AppLogger.fileSystem.info("Sync complete: \(stats.description)")
            
        } catch is CancellationError {
            AppLogger.fileSystem.info("Sync cancelled by user")
            await MainActor.run {
                errorMessage = "Sync cancelled"
            }
        } catch {
            AppLogger.fileSystem.error("Sync failed: \(error.localizedDescription)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        
        await MainActor.run {
            isSyncing = false
        }
    }
    
    // MARK: - File Processing
    
    private enum ProcessResult {
        case downloaded
        case skipped
    }
    
    /// Process a single file from the device.
    private func processFile(_ fileInfo: DeviceFileInfo) async throws -> ProcessResult {
        let filename = fileInfo.filename
        let expectedSize = fileInfo.size
        
        // Step A: Check if file already exists in database
        if let existing = try await repository.fetchByFilename(filename) {
            // Step B: Exact match - skip if size matches
            if existing.fileSizeBytes == expectedSize || existing.fileSizeBytes == nil {
                AppLogger.fileSystem.debug("Skipping \(filename) - already synced")
                return .skipped
            }
            
            // Step C: Conflict - same filename, different content
            // CRITICAL: Must rename existing file and update DB BEFORE inserting new
            try await resolveConflict(existing: existing)
        }
        
        // Step D: Download new file
        try await downloadAndStore(fileInfo)
        
        return .downloaded
    }
    
    /// Resolve a conflict where a file with the same name but different content exists.
    ///
    /// CRITICAL ORDER (required by UNIQUE constraint on filename):
    /// 1. Generate backup filename
    /// 2. Rename physical file
    /// 3. Update DB record with new filename
    /// 4. Now the original filename is free for the new file
    private func resolveConflict(existing: Recording) async throws {
        AppLogger.fileSystem.info("Resolving conflict for \(existing.filename)")
        
        // Generate backup name: "Recording.hda" -> "Recording_backup_1.hda"
        let backupFilename = try fileSystemService.generateBackupFilename(for: existing.filename)
        
        // Physical rename
        let existingURL = URL(fileURLWithPath: existing.filepath)
        let backupURL = try fileSystemService.renameFile(at: existingURL, to: backupFilename)
        
        // Get relative path for DB
        guard let backupRelativePath = fileSystemService.relativePath(for: backupURL) else {
            throw SyncError.conflictResolutionFailed("Could not determine relative path for backup")
        }
        
        // Update DB IMMEDIATELY (to free the UNIQUE filename constraint)
        try await repository.updateFilePath(
            id: existing.id,
            newRelativePath: backupRelativePath,
            newFilename: backupFilename
        )
        
        AppLogger.fileSystem.info("Conflict resolved: \(existing.filename) -> \(backupFilename)")
    }
    
    /// Download a file from device, validate it, and store in local storage.
    private func downloadAndStore(_ fileInfo: DeviceFileInfo) async throws {
        let filename = fileInfo.filename
        
        // Create temp file path
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("download_\(UUID().uuidString)_\(filename)")
        
        defer {
            // Cleanup temp file if it exists
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        // Download to temp
        AppLogger.fileSystem.info("Downloading \(filename) to temp...")
        try await deviceService.downloadFile(
            filename: filename,
            toPath: tempURL,
            progress: { _ in }
        )
        
        // Validate the download
        try await audioService.validateAsync(url: tempURL, expectedSize: fileInfo.size)
        
        // Move to storage
        let finalURL = try fileSystemService.moveToStorage(from: tempURL, filename: filename)
        
        // Verify storage path is resolvable
        guard fileSystemService.relativePath(for: finalURL) != nil else {
            throw SyncError.storagePathResolutionFailed
        }
        
        // Create Recording model with metadata from device
        let recording = Recording(
            id: 0, // Will be assigned by DB
            filename: filename,
            filepath: finalURL.path, // Repository will convert to relative on insert
            title: nil, // Can be set by user later
            durationSeconds: fileInfo.durationSeconds,
            fileSizeBytes: fileInfo.size,
            createdAt: fileInfo.createdAt ?? Date(),
            modifiedAt: Date(),
            deviceSerial: deviceService.connectionInfo?.serialNumber,
            deviceModel: deviceService.connectionInfo?.model.rawValue,
            recordingMode: fileInfo.mode,
            status: .downloaded,
            playbackPositionSeconds: 0
        )
        
        // Insert into repository
        _ = try await repository.insert(recording)
        
        AppLogger.fileSystem.info("Stored \(filename) successfully")
    }
    
    // MARK: - Manual Import
    
    /// Import audio files from user-selected URLs (drag-and-drop or file picker).
    ///
    /// - Parameter urls: Array of file URLs to import
    /// - Returns: Array of imported Recording models
    /// - Throws: Error if import fails
    func importFiles(_ urls: [URL]) async throws -> [Recording] {
        var imported: [Recording] = []
        
        for url in urls {
            // Get source file info
            let filename = url.lastPathComponent
            
            // Check if file with this name already exists
            if try await repository.fetchByFilename(filename) != nil {
                // Generate a unique name
                let uniqueFilename = try fileSystemService.generateBackupFilename(for: filename)
                let recording = try await importSingleFile(from: url, as: uniqueFilename)
                imported.append(recording)
            } else {
                let recording = try await importSingleFile(from: url, as: filename)
                imported.append(recording)
            }
        }
        
        AppLogger.fileSystem.info("Imported \(imported.count) files")
        return imported
    }
    
    /// Import a single file.
    private func importSingleFile(from sourceURL: URL, as filename: String) async throws -> Recording {
        // Start accessing security-scoped resource (for files from file picker)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Get file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        
        // Copy to storage
        let finalURL = try fileSystemService.copyToStorage(from: sourceURL, filename: filename)
        
        // Get duration
        let duration = try await audioService.getDuration(url: finalURL)
        
        // Create Recording
        let recording = Recording(
            id: 0,
            filename: filename,
            filepath: finalURL.path,
            title: nil,
            durationSeconds: duration,
            fileSizeBytes: fileSize,
            createdAt: attributes[.creationDate] as? Date ?? Date(),
            modifiedAt: Date(),
            deviceSerial: nil,
            deviceModel: nil,
            recordingMode: nil,
            status: .downloaded,
            playbackPositionSeconds: 0
        )
        
        return try await repository.insert(recording)
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case notConnected
    case conflictResolutionFailed(String)
    case downloadFailed(String)
    case validationFailed(String)
    case storagePathResolutionFailed
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No device connected"
        case .conflictResolutionFailed(let reason):
            return "Conflict resolution failed: \(reason)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .storagePathResolutionFailed:
            return "Could not determine storage path"
        }
    }
}

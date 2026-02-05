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
    func downloadFile(filename: String, expectedSize: Int, toPath: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws
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

/// Sync operation state machine
enum SyncState: Equatable, Sendable {
    /// Ready to sync
    case idle
    /// Sync requested, listing files from device
    case preparing
    /// Actively downloading files
    case syncing
    /// Stop requested, waiting for current file to finish
    case stopping
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

    private(set) var syncState: SyncState = .idle
    private(set) var currentFile: String?
    private(set) var errorMessage: String?
    private(set) var syncStats: SyncStats?

    /// Convenience property for UI bindings that just need to know if sync is active.
    var isSyncing: Bool {
        syncState != .idle
    }

    // Byte-level progress tracking
    private(set) var totalBytesExpected: Int64 = 0
    private(set) var totalBytesSynced: Int64 = 0
    private(set) var bytesPerSecond: Double = 0
    private(set) var estimatedSecondsRemaining: TimeInterval = 0

    var progress: Double {
        guard totalBytesExpected > 0 else { return 0 }
        return min(Double(totalBytesSynced) / Double(totalBytesExpected), 1.0)
    }

    var formattedBytesProgress: String {
        let synced = ByteCountFormatter.string(fromByteCount: totalBytesSynced, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytesExpected, countStyle: .file)
        return "\(synced) of \(total)"
    }

    var formattedSpeed: String {
        guard bytesPerSecond > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    var formattedTimeRemaining: String {
        guard estimatedSecondsRemaining > 1, bytesPerSecond > 0 else { return "" }
        let secs = Int(estimatedSecondsRemaining)
        if secs < 10 { return "a few seconds left" }
        if secs < 60 {
            let rounded = max((secs / 5) * 5, 5)
            return "about \(rounded) sec left"
        }
        let mins = (secs + 30) / 60
        if mins == 1 { return "about 1 min left" }
        if mins < 60 { return "about \(mins) min left" }
        let hrs = mins / 60
        let remMins = mins % 60
        if remMins == 0 { return "about \(hrs) hr left" }
        return "about \(hrs) hr \(remMins) min left"
    }

    var formattedTelemetry: String {
        var parts: [String] = []
        if !formattedSpeed.isEmpty { parts.append(formattedSpeed) }
        if !formattedTimeRemaining.isEmpty { parts.append(formattedTimeRemaining) }
        return parts.joined(separator: " \u{2022} ")
    }

    // MARK: - Private Progress Tracking

    private var completedBytes: Int64 = 0
    private var syncStartTime: Date = .distantPast
    private var lastStatsUpdateTime: Date = .distantPast
    /// Sliding window samples for speed calculation (last ~3 seconds)
    private var speedSamples: [(time: Date, bytes: Int64)] = []

    /// Task handle for the current sync operation, used for cancellation.
    private var syncTask: Task<Void, Never>?

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

    /// Synchronize all recordings from the connected HiDock device.
    func syncFromDevice() {
        guard !isSyncing else {
            AppLogger.fileSystem.warning("Sync already in progress")
            return
        }

        syncState = .preparing

        syncTask = Task {
            do {
                let deviceFiles = try await deviceService.listFiles()
                await performSync(files: deviceFiles)
            } catch is CancellationError {
                AppLogger.fileSystem.info("Sync preparation cancelled")
                await MainActor.run { syncState = .idle }
            } catch {
                AppLogger.fileSystem.error("Failed to list device files: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    syncState = .idle
                }
            }
            syncTask = nil
        }
    }

    /// Synchronize specific files from the connected HiDock device.
    func syncFiles(_ files: [DeviceFileInfo]) {
        guard !isSyncing else {
            AppLogger.fileSystem.warning("[sync] Sync already in progress — ignoring syncFiles call")
            return
        }
        let names = files.map(\.filename).joined(separator: ", ")
        AppLogger.fileSystem.info("[sync] syncFiles called with \(files.count) file(s): \(names)")

        // No preparation phase needed - files are already provided
        syncTask = Task {
            await performSync(files: files)
            syncTask = nil
        }
    }

    /// Cancel the currently running sync operation.
    func cancelSync() {
        guard isSyncing, let task = syncTask else {
            AppLogger.fileSystem.info("[sync] cancelSync called but no sync in progress")
            return
        }
        AppLogger.fileSystem.info("[sync] Cancelling sync...")
        syncState = .stopping
        task.cancel()
    }

    /// Shared sync pipeline for a given list of device files.
    private func performSync(files deviceFiles: [DeviceFileInfo]) async {
        completedBytes = 0
        syncStartTime = Date()
        lastStatsUpdateTime = .distantPast
        speedSamples = []

        await MainActor.run {
            syncState = .syncing
            totalBytesExpected = 0
            totalBytesSynced = 0
            bytesPerSecond = 0
            estimatedSecondsRemaining = 0
            currentFile = nil
            errorMessage = nil
            syncStats = nil
        }

        var downloaded = 0
        var skipped = 0
        var failed = 0
        var failedErrors: [String] = []

        do {
            try fileSystemService.ensureStorageDirectoryExists()

            let total = deviceFiles.count
            let totalBytes = deviceFiles.reduce(Int64(0)) { $0 + Int64($1.size) }

            await MainActor.run {
                totalBytesExpected = totalBytes
            }

            AppLogger.fileSystem.info("Starting sync: \(total) files, \(totalBytes) bytes")

            for fileInfo in deviceFiles {
                try Task.checkCancellation()

                await MainActor.run {
                    currentFile = fileInfo.filename
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
                    failedErrors.append("\(fileInfo.filename): \(error.localizedDescription)")
                }

                completedBytes += Int64(fileInfo.size)
                await MainActor.run {
                    totalBytesSynced = completedBytes
                }
            }

            let stats = SyncStats(total: total, downloaded: downloaded, skipped: skipped, failed: failed)
            let errorText = failed > 0 ? failedErrors.joined(separator: "\n") : nil
            await MainActor.run {
                syncStats = stats
                totalBytesSynced = totalBytesExpected
                currentFile = nil
                bytesPerSecond = 0
                estimatedSecondsRemaining = 0
                errorMessage = errorText
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
            syncState = .idle
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

        AppLogger.fileSystem.info("[sync] Processing \(filename) (\(expectedSize) bytes)")

        // Step A: Check if file already exists in database
        if let existing = try await repository.fetchByFilename(filename) {
            // Step B: Exact match - skip if size matches
            if existing.fileSizeBytes == expectedSize || existing.fileSizeBytes == nil {
                AppLogger.fileSystem.info("[sync] Skipping \(filename) — already synced (DB size: \(existing.fileSizeBytes ?? -1))")
                return .skipped
            }

            // Step C: Conflict - same filename, different content
            AppLogger.fileSystem.info("[sync] Conflict: \(filename) DB size=\(existing.fileSizeBytes ?? -1) vs device size=\(expectedSize)")
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
    
    /// Download a file from device, verify size, and store in local storage.
    ///
    /// Validation strategy: file size is the integrity check. AVFoundation
    /// validation is skipped because HiDock `.hda` files (MP3 data with a
    /// proprietary extension) are not reliably readable by AVURLAsset.
    /// The device already provides duration metadata, so we don't need
    /// AVFoundation to extract it.
    private func downloadAndStore(_ fileInfo: DeviceFileInfo) async throws {
        let filename = fileInfo.filename

        // Temp file keeps original extension — it doesn't matter since we
        // no longer run AVFoundation validation on device downloads.
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("download_\(UUID().uuidString)_\(filename)")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Download to temp
        AppLogger.fileSystem.info("[sync] Downloading \(filename) → \(tempURL.lastPathComponent)")
        try await deviceService.downloadFile(
            filename: filename,
            expectedSize: fileInfo.size,
            toPath: tempURL,
            progress: { bytesDownloaded, _ in
                self.updateSyncProgress(currentFileBytes: bytesDownloaded)
            }
        )

        // Verify file size — the real integrity check
        let downloadedAttrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let downloadedSize = downloadedAttrs[.size] as? Int ?? 0
        AppLogger.fileSystem.info("[sync] Download complete: \(filename), \(downloadedSize) of \(fileInfo.size) bytes")

        if downloadedSize != fileInfo.size {
            AppLogger.fileSystem.error("[sync] Size mismatch for \(filename): got \(downloadedSize), expected \(fileInfo.size)")
            throw SyncError.downloadIncomplete(
                filename: filename,
                expectedBytes: fileInfo.size,
                actualBytes: downloadedSize
            )
        }

        // Move to storage (preserves original filename and extension)
        let finalURL = try fileSystemService.moveToStorage(from: tempURL, filename: filename)
        AppLogger.fileSystem.info("[sync] Moved to storage: \(finalURL.path)")

        // Verify storage path is resolvable
        guard let relativePath = fileSystemService.relativePath(for: finalURL) else {
            AppLogger.fileSystem.error("[sync] Cannot resolve relative path for \(finalURL.path)")
            throw SyncError.storagePathResolutionFailed
        }
        AppLogger.fileSystem.debug("[sync] Relative path: \(relativePath)")

        // Create Recording model with metadata from device
        let recording = Recording(
            id: 0,
            filename: filename,
            filepath: finalURL.path,
            title: nil,
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
        let inserted = try await repository.insert(recording)
        AppLogger.fileSystem.info("[sync] Stored \(filename) → DB id=\(inserted.id)")
    }

    /// Update progress state from the USB download callback. Throttled to ~4 updates/sec.
    /// Speed is computed over a 3-second sliding window so it reflects the
    /// current transfer rate rather than the diluted overall average.
    private func updateSyncProgress(currentFileBytes: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastStatsUpdateTime) >= 0.25 else { return }
        lastStatsUpdateTime = now

        let cappedCurrent = min(currentFileBytes, Int64(totalBytesExpected - completedBytes))
        let globalBytes = completedBytes + max(cappedCurrent, 0)

        // Sliding window: keep samples from the last 3 seconds
        speedSamples.append((time: now, bytes: globalBytes))
        speedSamples.removeAll { now.timeIntervalSince($0.time) > 3.0 }

        let speed: Double
        if let oldest = speedSamples.first, speedSamples.count >= 2 {
            let dt = now.timeIntervalSince(oldest.time)
            let db = Double(globalBytes - oldest.bytes)
            speed = dt > 0.1 ? db / dt : 0
        } else {
            speed = 0
        }

        let remaining: TimeInterval = speed > 0
            ? Double(totalBytesExpected - globalBytes) / speed
            : 0

        Task { @MainActor in
            self.totalBytesSynced = globalBytes
            self.bytesPerSecond = speed
            self.estimatedSecondsRemaining = remaining
        }
    }

    // MARK: - Manual Import
    
    /// Import audio files from user-selected URLs (drag-and-drop or file picker).
    ///
    /// - Parameter urls: Array of file URLs to import
    /// - Returns: Array of imported Recording models
    /// - Throws: Error if import fails
    func importFiles(_ urls: [URL]) async throws -> [Recording] {
        AppLogger.fileSystem.info("[import] importFiles called with \(urls.count) URL(s)")
        var imported: [Recording] = []

        for url in urls {
            let filename = url.lastPathComponent
            AppLogger.fileSystem.info("[import] Processing \(filename) from \(url.path)")

            // Check if file with this name already exists
            if try await repository.fetchByFilename(filename) != nil {
                let uniqueFilename = try fileSystemService.generateBackupFilename(for: filename)
                AppLogger.fileSystem.info("[import] Name conflict — using \(uniqueFilename)")
                let recording = try await importSingleFile(from: url, as: uniqueFilename)
                imported.append(recording)
            } else {
                let recording = try await importSingleFile(from: url, as: filename)
                imported.append(recording)
            }
        }

        AppLogger.fileSystem.info("[import] Imported \(imported.count) of \(urls.count) files")
        return imported
    }
    
    /// Import a single file.
    private func importSingleFile(from sourceURL: URL, as filename: String) async throws -> Recording {
        AppLogger.fileSystem.info("[import] Importing \(sourceURL.lastPathComponent) as \(filename)")

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
        AppLogger.fileSystem.info("[import] Source file size: \(fileSize) bytes")

        // Copy to storage
        let finalURL = try fileSystemService.copyToStorage(from: sourceURL, filename: filename)
        AppLogger.fileSystem.info("[import] Copied to storage: \(finalURL.path)")

        // Get duration
        let duration = try await audioService.getDuration(url: finalURL)
        AppLogger.fileSystem.info("[import] Duration: \(duration)s")
        
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
        
        let inserted = try await repository.insert(recording)
        AppLogger.fileSystem.info("[import] Stored \(filename) → DB id=\(inserted.id)")
        return inserted
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case notConnected
    case conflictResolutionFailed(String)
    case downloadFailed(String)
    case downloadIncomplete(filename: String, expectedBytes: Int, actualBytes: Int)
    case validationFailed(String)
    case storagePathResolutionFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No HiDock device is connected. Please reconnect and try again."
        case .conflictResolutionFailed(let reason):
            return "Could not resolve a file name conflict: \(reason)"
        case .downloadFailed(let reason):
            return "The file could not be downloaded from the device: \(reason)"
        case .downloadIncomplete(let filename, let expected, let actual):
            let pct = expected > 0 ? Int(Double(actual) / Double(expected) * 100) : 0
            return "\"\(filename)\" was only partially downloaded (\(pct)%). Please try again."
        case .validationFailed(let reason):
            return "The downloaded file appears to be corrupted: \(reason)"
        case .storagePathResolutionFailed:
            return "Could not save the file to the recordings folder. Check that the storage location is accessible."
        }
    }
}

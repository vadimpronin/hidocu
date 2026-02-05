//
//  RecordingImportService.swift
//  HiDocu
//
//  Core import engine for downloading recordings from HiDock devices.
//  Handles conflict resolution, progress tracking, and file validation.
//

import Foundation
import SwiftUI
import Observation

// MARK: - Import Session

@Observable
final class ImportSession: Identifiable {
    let id: UUID = UUID()
    let deviceID: UInt64
    
    // MARK: - State
    
    var importState: ImportState = .idle
    var currentFile: String?
    var errorMessage: String?
    var importStats: ImportStats?
    
    var isImporting: Bool {
        importState != .idle
    }
    
    // MARK: - Progress Tracking
    
    var totalBytesExpected: Int64 = 0
    var totalBytesImported: Int64 = 0
    var bytesPerSecond: Double = 0
    var estimatedSecondsRemaining: TimeInterval = 0
    
    // Internal tracking
    var completedBytes: Int64 = 0
    var speedSamples: [(time: Date, bytes: Int64)] = []
    
    // MARK: - Initialization
    
    init(deviceID: UInt64) {
        self.deviceID = deviceID
    }
    
    // MARK: - Reset
    
    func reset() {
        importState = .idle
        currentFile = nil
        errorMessage = nil
        importStats = nil
        totalBytesExpected = 0
        totalBytesImported = 0
        bytesPerSecond = 0
        estimatedSecondsRemaining = 0
        completedBytes = 0
        speedSamples = []
    }
    
    // MARK: - Formatters
    
    var progress: Double {
        guard totalBytesExpected > 0 else { return 0 }
        return min(Double(totalBytesImported) / Double(totalBytesExpected), 1.0)
    }
    
    var formattedBytesProgress: String {
        let imported = ByteCountFormatter.string(fromByteCount: totalBytesImported, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytesExpected, countStyle: .file)
        return "\(imported) of \(total)"
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
}

/// Narrow protocol covering only what the import service needs from a device.
/// `DeviceConnectionService` is `@Observable` (not `Sendable`), so it cannot
/// conform to `DeviceRepository`. This protocol avoids that constraint.
protocol DeviceFileProvider {
    var connectionInfo: DeviceConnectionInfo? { get }
    func listFiles() async throws -> [DeviceFileInfo]
    func downloadFile(filename: String, expectedSize: Int, toPath: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws
}

/// Statistics from an import operation
struct ImportStats: Sendable {
    let total: Int
    let downloaded: Int
    let skipped: Int
    let failed: Int

    var description: String {
        "Total: \(total), Downloaded: \(downloaded), Skipped: \(skipped), Failed: \(failed)"
    }
}

/// Import operation state machine
enum ImportState: Equatable, Sendable {
    /// Ready to import
    case idle
    /// Import requested, listing files from device
    case preparing
    /// Actively downloading files
    case importing
    /// Stop requested, waiting for current file to finish
    case stopping
}

/// Observable service for importing recordings from HiDock device to local storage.
///
/// The import algorithm handles:
/// 1. Skip files that already exist with matching size
/// 2. Conflict resolution for same filename but different content
/// 3. Download to temp, validate, then move to storage
/// 4. Proper metadata extraction from device
///
/// - Important: The UNIQUE constraint on `filename` in the database dictates that
///   conflict resolution (rename existing file) must happen BEFORE inserting new file.
@Observable
final class RecordingImportService {

    // MARK: - Session Management
    
    // Active sessions keyed by device ID (IOKit registry entry ID)
    private var sessions: [UInt64: ImportSession] = [:]
    
    // Sessions for manual imports/generic tasks
    private var manualSessions: [UUID: ImportSession] = [:]
    
    /// Get the session for a specific device.
    func session(for deviceId: UInt64) -> ImportSession? {
        sessions[deviceId]
    }
    
    // MARK: - Observing Import Status
    
    /// True if ANY import is active (legacy support, or for global spinner)
    var isImporting: Bool {
        !sessions.isEmpty || !manualSessions.isEmpty
    }
    
    /// Returns the first error message from any active session, if any.
    var errorMessage: String? {
        sessions.values.compactMap(\.errorMessage).first
    }

    // MARK: - Dependencies

    private let fileSystemService: FileSystemService
    private let audioService: AudioCompatibilityService
    private let repository: any RecordingRepository

    // MARK: - Initialization

    init(
        fileSystemService: FileSystemService,
        audioService: AudioCompatibilityService,
        repository: any RecordingRepository
    ) {
        self.fileSystemService = fileSystemService
        self.audioService = audioService
        self.repository = repository

        AppLogger.fileSystem.info("RecordingImportService initialized")
    }

    // MARK: - Import from Device

    /// Import all recordings from the connected HiDock device.
    func importFromDevice(controller: any DeviceFileProvider) {
        let deviceID = (controller as? DeviceController)?.id ?? 0
        
        // Prevent duplicate import for same device
        if let existing = sessions[deviceID], existing.isImporting {
            AppLogger.fileSystem.warning("Import already in progress for device \(deviceID)")
            return
        }
        
        let session = ImportSession(deviceID: deviceID)
        sessions[deviceID] = session
        
        session.importState = .preparing

        Task {
            do {
                let deviceFiles = try await controller.listFiles()
                await performImport(files: deviceFiles, from: controller, session: session)
            } catch is CancellationError {
                AppLogger.fileSystem.info("Import preparation cancelled")
                session.importState = .idle
            } catch {
                AppLogger.fileSystem.error("Failed to list device files: \(error.localizedDescription)")
                session.errorMessage = error.localizedDescription
                session.importState = .idle
            }
            
            // Cleanup session if idle
            if session.importState == .idle {
                sessions.removeValue(forKey: deviceID)
            }
        }
    }

    /// Import specific files from the connected HiDock device.
    func importDeviceFiles(_ files: [DeviceFileInfo], from controller: any DeviceFileProvider) {
        let deviceID = (controller as? DeviceController)?.id ?? 0
        
        if let existing = sessions[deviceID], existing.isImporting {
            AppLogger.fileSystem.warning("[import] Import already in progress for device \(deviceID) — ignoring importDeviceFiles call")
            return
        }
        
        let session = ImportSession(deviceID: deviceID)
        sessions[deviceID] = session
        
        let names = files.map(\.filename).joined(separator: ", ")
        AppLogger.fileSystem.info("[import] importDeviceFiles called with \(files.count) file(s): \(names)")

        Task {
            await performImport(files: files, from: controller, session: session)
             // Cleanup
            sessions.removeValue(forKey: deviceID)
        }
    }

    /// Cancel the currently running import operation for a specific device.
    func cancelImport(for deviceID: UInt64) {
        guard let session = sessions[deviceID], session.isImporting else {
            AppLogger.fileSystem.info("[import] cancelImport called but no active session for device \(deviceID)")
            return
        }
        AppLogger.fileSystem.info("[import] Cancelling import for device \(deviceID)...")
        session.importState = .stopping
        // Note: The Task inside performImport checks for cancellation state or flags.
        // Since we don't hold the Task reference directly in the Session anymore (it's implicit),
        // we rely on the implementation of performImport to check `session.importState == .stopping`.
    }

    /// Shared import pipeline for a given list of device files.
    private func performImport(files deviceFiles: [DeviceFileInfo], from controller: any DeviceFileProvider, session: ImportSession) async {
        session.reset()
        
        await MainActor.run {
            session.importState = .importing
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
                session.totalBytesExpected = totalBytes
            }

            AppLogger.fileSystem.info("Starting import: \(total) files, \(totalBytes) bytes")

            for fileInfo in deviceFiles {
                try Task.checkCancellation()
                
                // Check if stop requested
                if session.importState == .stopping {
                     throw CancellationError()
                }

                await MainActor.run {
                    session.currentFile = fileInfo.filename
                }

                do {
                    let result = try await processFile(fileInfo, from: controller, session: session)
                    switch result {
                    case .downloaded:
                        downloaded += 1
                    case .skipped:
                        skipped += 1
                    }
                } catch {
                    AppLogger.fileSystem.error("Failed to import \(fileInfo.filename): \(error.localizedDescription)")
                    failed += 1
                    failedErrors.append("\(fileInfo.filename): \(error.localizedDescription)")
                }

                session.completedBytes += Int64(fileInfo.size)
                await MainActor.run {
                    session.totalBytesImported = session.completedBytes
                }
            }

            let stats = ImportStats(total: total, downloaded: downloaded, skipped: skipped, failed: failed)
            let errorText = failed > 0 ? failedErrors.joined(separator: "\n") : nil
            await MainActor.run {
                session.importStats = stats
                session.totalBytesImported = session.totalBytesExpected
                session.currentFile = nil
                session.bytesPerSecond = 0
                session.estimatedSecondsRemaining = 0
                session.errorMessage = errorText
            }

            AppLogger.fileSystem.info("Import complete: \(stats.description)")

        } catch is CancellationError {
            AppLogger.fileSystem.info("Import cancelled by user")
            await MainActor.run {
                session.errorMessage = "Import cancelled"
            }
        } catch {
            AppLogger.fileSystem.error("Import failed: \(error.localizedDescription)")
            await MainActor.run {
                session.errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            session.importState = .idle
        }
    }

    // MARK: - File Processing

    private enum ProcessResult {
        case downloaded
        case skipped
    }

    /// Process a single file from the device.
    private func processFile(_ fileInfo: DeviceFileInfo, from controller: any DeviceFileProvider, session: ImportSession) async throws -> ProcessResult {
        let filename = fileInfo.filename
        let expectedSize = fileInfo.size

        AppLogger.fileSystem.info("[import] Processing \(filename) (\(expectedSize) bytes)")

        // Step A: Check if file already exists in database
        if let existing = try await repository.fetchByFilename(filename) {
            // Step B: Exact match - skip if size matches
            if existing.fileSizeBytes == expectedSize || existing.fileSizeBytes == nil {
                AppLogger.fileSystem.info("[import] Skipping \(filename) — already imported (DB size: \(existing.fileSizeBytes ?? -1))")
                return .skipped
            }

            // Step C: Conflict - same filename, different content
            AppLogger.fileSystem.info("[import] Conflict: \(filename) DB size=\(existing.fileSizeBytes ?? -1) vs device size=\(expectedSize)")
            try await resolveConflict(existing: existing)
        }

        // Step D: Download new file
        try await downloadAndStore(fileInfo, from: controller, session: session)

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
            throw ImportError.conflictResolutionFailed("Could not determine relative path for backup")
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
    private func downloadAndStore(_ fileInfo: DeviceFileInfo, from controller: any DeviceFileProvider, session: ImportSession) async throws {
        let filename = fileInfo.filename
        let tempDir = FileManager.default.temporaryDirectory
        // Use unique temp file to handle parallel downloads safely
        let tempURL = tempDir.appendingPathComponent("download_\(session.deviceID)_\(UUID().uuidString)_\(filename)")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Download to temp
        AppLogger.fileSystem.info("[import] Downloading \(filename) → \(tempURL.lastPathComponent)")
        try await controller.downloadFile(
            filename: filename,
            expectedSize: fileInfo.size,
            toPath: tempURL,
            progress: { bytesDownloaded, _ in
                self.updateImportProgress(currentFileBytes: bytesDownloaded, session: session)
            }
        )
        // ... rest of validation and storage logic is largely same but check session state
        
        // Verify file size
        let downloadedAttrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let downloadedSize = downloadedAttrs[.size] as? Int ?? 0
        
        if downloadedSize != fileInfo.size {
             throw ImportError.downloadIncomplete(filename: filename, expectedBytes: fileInfo.size, actualBytes: downloadedSize)
        }

        // Move to storage
        let finalURL = try fileSystemService.moveToStorage(from: tempURL, filename: filename)
        
        // Get Relative Path
        // Get Relative Path
        guard fileSystemService.relativePath(for: finalURL) != nil else {
             throw ImportError.storagePathResolutionFailed
        }

        // Create Model
        let recording = Recording(
            id: 0,
            filename: filename,
            filepath: finalURL.path,
            title: nil, // TODO: Use actual duration
            durationSeconds: fileInfo.durationSeconds,
            fileSizeBytes: fileInfo.size,
            createdAt: fileInfo.createdAt ?? Date(),
            modifiedAt: Date(),
            deviceSerial: controller.connectionInfo?.serialNumber,
            deviceModel: controller.connectionInfo?.model.rawValue,
            recordingMode: fileInfo.mode,
            status: .downloaded,
            playbackPositionSeconds: 0
        )

        // Insert
        _ = try await repository.insert(recording)
    }

    /// Update progress state from the USB download callback.
    private func updateImportProgress(currentFileBytes: Int64, session: ImportSession) {
        let now = Date()
        
        // Use session-local tracking
        // Note: speedSamples need to be stored in the Session object not global service
        
        // Simple update for now to avoid complexity of moving sliding window logic right this second
        // or assumes session has the properties.
        
        let cappedCurrent = min(currentFileBytes, Int64(session.totalBytesExpected - session.completedBytes))
        let globalBytes = session.completedBytes + max(cappedCurrent, 0)
        
        // Sliding window logic needs to be per-session
        session.speedSamples.append((time: now, bytes: globalBytes))
        session.speedSamples.removeAll { now.timeIntervalSince($0.time) > 3.0 }
        
        let speed: Double
        if let oldest = session.speedSamples.first, session.speedSamples.count >= 2 {
            let dt = now.timeIntervalSince(oldest.time)
            let db = Double(globalBytes - oldest.bytes)
            speed = dt > 0.1 ? db / dt : 0
        } else {
            speed = 0
        }
        
         let remaining: TimeInterval = speed > 0
            ? Double(session.totalBytesExpected - globalBytes) / speed
            : 0

        Task { @MainActor in
            session.totalBytesImported = globalBytes
            session.bytesPerSecond = speed
            session.estimatedSecondsRemaining = remaining
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

enum ImportError: LocalizedError {
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

//
//  RecordingSourceService.swift
//  HiDocu
//
//  Business logic for managing recording sources and their recordings.
//

import Foundation

final class RecordingSourceService {

    private let recordingSourceRepository: any RecordingSourceRepository
    private let recordingRepository: any RecordingRepositoryV2
    private let fileSystemService: FileSystemService

    init(
        recordingSourceRepository: any RecordingSourceRepository,
        recordingRepository: any RecordingRepositoryV2,
        fileSystemService: FileSystemService
    ) {
        self.recordingSourceRepository = recordingSourceRepository
        self.recordingRepository = recordingRepository
        self.fileSystemService = fileSystemService
        AppLogger.recordings.info("RecordingSourceService initialized")
    }

    // MARK: - Source Management

    /// Upsert a recording source for a HiDock device.
    /// Creates a new source if none exists for this serial number, otherwise updates lastSeenAt.
    func ensureSourceForDevice(
        serialNumber: String,
        model: String,
        displayName: String
    ) async throws -> RecordingSource {
        // Check if source already exists by unique identifier (serial number)
        if let existing = try await recordingSourceRepository.fetchByUniqueIdentifier(serialNumber) {
            try await recordingSourceRepository.updateLastSeen(id: existing.id, at: Date())
            AppLogger.recordings.info("Updated lastSeenAt for existing source: \(existing.name) (id=\(existing.id))")
            return existing
        }

        // Create new source
        let directory = Self.directoryName(model: model, serial: serialNumber)
        let source = RecordingSource(
            name: displayName,
            type: .hidock,
            uniqueIdentifier: serialNumber,
            directory: directory,
            deviceModel: model,
            lastSeenAt: Date()
        )

        let inserted = try await recordingSourceRepository.insert(source)
        AppLogger.recordings.info("Created new recording source: \(inserted.name) (id=\(inserted.id), dir=\(directory))")
        return inserted
    }

    /// Get or create the "Imported" source for manual file imports.
    func ensureImportSource() async throws -> RecordingSource {
        let importIdentifier = "manual-import"

        if let existing = try await recordingSourceRepository.fetchByUniqueIdentifier(importIdentifier) {
            return existing
        }

        let source = RecordingSource(
            name: "Imported",
            type: .upload,
            uniqueIdentifier: importIdentifier,
            directory: "Imported"
        )

        let inserted = try await recordingSourceRepository.insert(source)
        AppLogger.recordings.info("Created manual import source (id=\(inserted.id))")
        return inserted
    }

    // MARK: - Timestamps

    func markSeen(sourceId: Int64) async throws {
        try await recordingSourceRepository.updateLastSeen(id: sourceId, at: Date())
    }

    func markSynced(sourceId: Int64) async throws {
        try await recordingSourceRepository.updateLastSynced(id: sourceId, at: Date())
    }

    // MARK: - Recording Management

    /// Create a new recording entry linked to a recording source.
    func createRecording(
        filename: String,
        filepath: String,
        sourceId: Int64,
        title: String? = nil,
        fileSizeBytes: Int? = nil,
        durationSeconds: Int? = nil,
        deviceSerial: String? = nil,
        deviceModel: String? = nil,
        recordingMode: RecordingMode? = nil,
        syncStatus: RecordingSyncStatus = .localOnly
    ) async throws -> RecordingV2 {
        let recording = RecordingV2(
            filename: filename,
            filepath: filepath,
            title: title,
            fileSizeBytes: fileSizeBytes,
            durationSeconds: durationSeconds,
            deviceSerial: deviceSerial,
            deviceModel: deviceModel,
            recordingMode: recordingMode,
            recordingSourceId: sourceId,
            syncStatus: syncStatus
        )

        let inserted = try await recordingRepository.insert(recording)
        AppLogger.recordings.info("Created recording: \(filename) (id=\(inserted.id), source=\(sourceId))")
        return inserted
    }

    // MARK: - Delete Local Copy

    /// Delete the local copy of a recording file.
    /// For HiDock sources: updates sync status to onDeviceOnly, then removes file from disk.
    /// For upload sources: deletes recording from DB, then removes file from disk.
    func deleteLocalCopy(recordingId: Int64) async throws {
        guard let recording = try await recordingRepository.fetchById(recordingId) else {
            AppLogger.recordings.warning("deleteLocalCopy: recording \(recordingId) not found")
            return
        }

        let fileURL = fileSystemService.recordingFileURL(relativePath: recording.filepath)

        // Update DB first to avoid inconsistent state if DB operation fails
        let isHiDockSource: Bool
        if let sourceId = recording.recordingSourceId,
           let source = try await recordingSourceRepository.fetchById(sourceId) {
            if source.type == .hidock {
                try await recordingRepository.updateSyncStatus(id: recordingId, syncStatus: .onDeviceOnly)
                AppLogger.recordings.info("Reverted recording \(recordingId) to onDeviceOnly")
                isHiDockSource = true
            } else {
                try await recordingRepository.delete(id: recordingId)
                AppLogger.recordings.info("Deleted upload recording \(recordingId) from DB")
                isHiDockSource = false
            }
        } else {
            try await recordingRepository.delete(id: recordingId)
            isHiDockSource = false
        }

        // Delete file from disk after DB is updated.
        // Call removeItem directly and handle "file not found" gracefully (avoids TOCTOU race).
        do {
            try FileManager.default.removeItem(at: fileURL)
            AppLogger.recordings.info("Deleted local file: \(recording.filepath)")
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            AppLogger.recordings.info("File already removed: \(recording.filepath)")
        } catch {
            // File deletion failed — attempt to roll back DB change for non-HiDock sources
            // to avoid orphaned files with no DB record
            if !isHiDockSource {
                AppLogger.recordings.error("File deletion failed, re-inserting recording \(recordingId): \(error.localizedDescription)")
                _ = try? await recordingRepository.insert(recording)
            } else {
                AppLogger.recordings.error("File deletion failed for recording \(recordingId): \(error.localizedDescription)")
            }
            throw error
        }
    }

    // MARK: - Dedup Helpers

    /// Check if a recording with the given filename already exists for a specific source.
    func recordingExists(filename: String, sourceId: Int64) async throws -> Bool {
        try await recordingRepository.existsByFilenameAndSourceId(filename, sourceId: sourceId)
    }

    /// Fetch all imported filenames for a source (batch dedup).
    func importedFilenames(for sourceId: Int64) async throws -> Set<String> {
        try await recordingRepository.fetchFilenamesForSource(sourceId)
    }

    // MARK: - Directory Naming

    /// Generate a sanitized directory name for a device source.
    /// Format: "Model_SerialNumber" (e.g., "HiDock_H1_SN12345")
    static func directoryName(model: String, serial: String) -> String {
        let raw = "\(model)_\(serial)"
        return PathSanitizer.sanitize(raw)
    }
}

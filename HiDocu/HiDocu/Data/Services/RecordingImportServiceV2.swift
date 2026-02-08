//
//  RecordingImportServiceV2.swift
//  HiDocu
//
//  Import service for context management system.
//  Creates Document + Source entities from device recordings and manual imports.
//

import Foundation

// MARK: - Import Session

@Observable
final class ImportSession: Identifiable {
    let id: UUID = UUID()
    let deviceID: UInt64

    var importState: ImportState = .idle
    var currentFile: String?
    var errorMessage: String?
    var importStats: ImportStats?

    var isImporting: Bool {
        importState != .idle
    }

    var totalBytesExpected: Int64 = 0
    var totalBytesImported: Int64 = 0
    var bytesPerSecond: Double = 0
    var estimatedSecondsRemaining: TimeInterval = 0

    var completedBytes: Int64 = 0
    var speedSamples: [(time: Date, bytes: Int64)] = []

    init(deviceID: UInt64) {
        self.deviceID = deviceID
    }

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
    case idle
    case preparing
    case importing
    case stopping
}

/// Import errors
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

// MARK: - Import Service

@Observable
final class RecordingImportServiceV2 {

    // MARK: - Session Management

    private var sessions: [UInt64: ImportSession] = [:]

    func session(for deviceId: UInt64) -> ImportSession? {
        sessions[deviceId]
    }

    var isImporting: Bool {
        !sessions.isEmpty
    }

    var errorMessage: String? {
        sessions.values.compactMap(\.errorMessage).first
    }

    // MARK: - Dependencies

    private let fileSystemService: FileSystemService
    private let documentService: DocumentService
    private let sourceRepository: any SourceRepository

    init(
        fileSystemService: FileSystemService,
        documentService: DocumentService,
        sourceRepository: any SourceRepository
    ) {
        self.fileSystemService = fileSystemService
        self.documentService = documentService
        self.sourceRepository = sourceRepository
        AppLogger.fileSystem.info("RecordingImportServiceV2 initialized")
    }

    // MARK: - Import from Device

    func importFromDevice(controller: any DeviceFileProvider) {
        let deviceID = (controller as? DeviceController)?.id ?? 0

        if let existing = sessions[deviceID], existing.isImporting {
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
                session.importState = .idle
            } catch {
                AppLogger.fileSystem.error("Failed to list device files: \(error.localizedDescription)")
                session.errorMessage = error.localizedDescription
                session.importState = .idle
            }

            if session.importState == .idle {
                sessions.removeValue(forKey: deviceID)
            }
        }
    }

    func importDeviceFiles(_ files: [DeviceFileInfo], from controller: any DeviceFileProvider) {
        let deviceID = (controller as? DeviceController)?.id ?? 0

        if let existing = sessions[deviceID], existing.isImporting {
            return
        }

        let session = ImportSession(deviceID: deviceID)
        sessions[deviceID] = session

        Task {
            await performImport(files: files, from: controller, session: session)
            sessions.removeValue(forKey: deviceID)
        }
    }

    func cancelImport(for deviceID: UInt64) {
        guard let session = sessions[deviceID], session.isImporting else { return }
        session.importState = .stopping
    }

    private func performImport(files deviceFiles: [DeviceFileInfo], from controller: any DeviceFileProvider, session: ImportSession) async {
        session.reset()

        await MainActor.run {
            session.importState = .importing
        }

        var downloaded = 0
        var skipped = 0
        var failed = 0

        do {
            try fileSystemService.ensureDataDirectoryExists()

            let total = deviceFiles.count
            let totalBytes = deviceFiles.reduce(Int64(0)) { $0 + Int64($1.size) }

            await MainActor.run {
                session.totalBytesExpected = totalBytes
            }

            for fileInfo in deviceFiles {
                try Task.checkCancellation()

                if session.importState == .stopping {
                    throw CancellationError()
                }

                await MainActor.run {
                    session.currentFile = fileInfo.filename
                }

                do {
                    let result = try await processFile(fileInfo, from: controller, session: session)
                    switch result {
                    case .downloaded: downloaded += 1
                    case .skipped: skipped += 1
                    }
                } catch {
                    AppLogger.fileSystem.error("Failed to import \(fileInfo.filename): \(error.localizedDescription)")
                    failed += 1
                }

                await MainActor.run {
                    session.completedBytes += Int64(fileInfo.size)
                    session.totalBytesImported = session.completedBytes
                }
            }

            let stats = ImportStats(total: total, downloaded: downloaded, skipped: skipped, failed: failed)
            await MainActor.run {
                session.importStats = stats
                session.totalBytesImported = session.totalBytesExpected
                session.currentFile = nil
            }

        } catch is CancellationError {
            await MainActor.run { session.errorMessage = "Import cancelled" }
        } catch {
            await MainActor.run { session.errorMessage = error.localizedDescription }
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

    private func processFile(_ fileInfo: DeviceFileInfo, from controller: any DeviceFileProvider, session: ImportSession) async throws -> ProcessResult {
        let filename = fileInfo.filename

        // Dedup: check if a Source with this displayName already exists
        if try await sourceRepository.existsByDisplayName(filename) {
            return .skipped
        }

        try await downloadAndStore(fileInfo, from: controller, session: session)
        return .downloaded
    }

    private func downloadAndStore(_ fileInfo: DeviceFileInfo, from controller: any DeviceFileProvider, session: ImportSession) async throws {
        let filename = fileInfo.filename
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("download_v2_\(UUID().uuidString)_\(filename)")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try await controller.downloadFile(
            filename: filename,
            expectedSize: fileInfo.size,
            toPath: tempURL,
            progress: { _, _ in }
        )

        // Verify size
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let downloadedSize = attrs[.size] as? Int ?? 0
        if downloadedSize != fileInfo.size {
            throw ImportError.downloadIncomplete(filename: filename, expectedBytes: fileInfo.size, actualBytes: downloadedSize)
        }

        // Move audio to date-organized directory
        let recordingDate = fileInfo.createdAt ?? Date()
        let audioRelativePath = try fileSystemService.moveAudioToRecordings(
            from: tempURL,
            filename: filename,
            date: recordingDate
        )

        // Generate document title
        let title = Self.documentTitle(for: recordingDate, durationSeconds: fileInfo.durationSeconds)

        // Create Document + Source
        do {
            _ = try await documentService.createDocumentWithSource(
                title: title,
                audioRelativePath: audioRelativePath,
                originalFilename: filename,
                durationSeconds: fileInfo.durationSeconds,
                fileSizeBytes: fileInfo.size,
                deviceSerial: controller.connectionInfo?.serialNumber,
                deviceModel: controller.connectionInfo?.model.rawValue,
                recordingMode: fileInfo.mode?.rawValue,
                recordedAt: recordingDate
            )
        } catch {
            // Cleanup orphaned audio file
            let audioURL = fileSystemService.dataDirectory.appendingPathComponent(audioRelativePath)
            try? FileManager.default.removeItem(at: audioURL)
            throw error
        }
    }

    // MARK: - Manual Import

    func importFiles(_ urls: [URL]) async throws -> [Document] {
        var imported: [Document] = []

        for url in urls {
            let filename = url.lastPathComponent

            // Skip if already exists
            if (try? await sourceRepository.existsByDisplayName(filename)) == true {
                continue
            }

            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attrs[.size] as? Int ?? 0
                let creationDate = attrs[.creationDate] as? Date ?? Date()

                let audioRelativePath = try fileSystemService.copyAudioToRecordings(
                    from: url,
                    filename: filename,
                    date: creationDate
                )

                let title = Self.documentTitle(for: creationDate, durationSeconds: nil)

                do {
                    let (doc, _) = try await documentService.createDocumentWithSource(
                        title: title,
                        audioRelativePath: audioRelativePath,
                        originalFilename: filename,
                        durationSeconds: nil,
                        fileSizeBytes: fileSize,
                        deviceSerial: nil,
                        deviceModel: nil,
                        recordingMode: nil,
                        recordedAt: creationDate
                    )
                    imported.append(doc)
                } catch {
                    // Cleanup orphaned audio
                    let audioURL = fileSystemService.dataDirectory.appendingPathComponent(audioRelativePath)
                    try? FileManager.default.removeItem(at: audioURL)
                    AppLogger.fileSystem.error("Failed to create document for \(filename): \(error.localizedDescription)")
                }
            } catch {
                AppLogger.fileSystem.error("Failed to import \(filename): \(error.localizedDescription)")
            }
        }

        return imported
    }

    // MARK: - Title Formatting

    static func documentTitle(for date: Date, durationSeconds: Int?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: date)
        if let seconds = durationSeconds, seconds > 0 {
            let minutes = max(seconds / 60, 1)
            return "Recording \(dateString) (\(minutes) min)"
        }
        return "Recording \(dateString)"
    }
}

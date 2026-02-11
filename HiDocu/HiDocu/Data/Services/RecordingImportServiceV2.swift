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
    private let transcriptRepository: any TranscriptRepository
    private let llmService: LLMService
    private let llmQueueService: LLMQueueService
    private let settingsService: SettingsService
    private let recordingSourceService: RecordingSourceService
    private let recordingRepository: any RecordingRepositoryV2

    init(
        fileSystemService: FileSystemService,
        documentService: DocumentService,
        sourceRepository: any SourceRepository,
        transcriptRepository: any TranscriptRepository,
        llmService: LLMService,
        llmQueueService: LLMQueueService,
        settingsService: SettingsService,
        recordingSourceService: RecordingSourceService,
        recordingRepository: any RecordingRepositoryV2
    ) {
        self.fileSystemService = fileSystemService
        self.documentService = documentService
        self.sourceRepository = sourceRepository
        self.transcriptRepository = transcriptRepository
        self.llmService = llmService
        self.llmQueueService = llmQueueService
        self.settingsService = settingsService
        self.recordingSourceService = recordingSourceService
        self.recordingRepository = recordingRepository
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

    func importDeviceFiles(_ files: [DeviceFileInfo], from controller: any DeviceFileProvider, createDocument: Bool = true) {
        let deviceID = (controller as? DeviceController)?.id ?? 0

        if let existing = sessions[deviceID], existing.isImporting {
            return
        }

        let session = ImportSession(deviceID: deviceID)
        sessions[deviceID] = session
        session.importState = .preparing

        Task {
            await performImport(files: files, from: controller, session: session, createDocument: createDocument)
            sessions.removeValue(forKey: deviceID)
        }
    }

    func cancelImport(for deviceID: UInt64) {
        guard let session = sessions[deviceID], session.isImporting else { return }
        session.importState = .stopping
    }

    private func performImport(files deviceFiles: [DeviceFileInfo], from controller: any DeviceFileProvider, session: ImportSession, createDocument: Bool = true) async {
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
                    let result = try await processFile(fileInfo, from: controller, session: session, createDocument: createDocument)
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

    private func processFile(_ fileInfo: DeviceFileInfo, from controller: any DeviceFileProvider, session: ImportSession, createDocument: Bool = true) async throws -> ProcessResult {
        let filename = fileInfo.filename

        // Get the recording source ID from the controller
        let sourceId = (controller as? DeviceController)?.recordingSourceId

        // Dedup: check scoped to recording source if available, otherwise fall back to display name
        if let sourceId {
            if let existing = try await recordingRepository.fetchByFilenameAndSourceId(filename, sourceId: sourceId) {
                if existing.syncStatus != .onDeviceOnly {
                    return .skipped  // already imported (.synced or .localOnly)
                }
                // Device-only record exists — download and update it in place
                try await downloadAndStore(fileInfo, from: controller, session: session, existingRecordingId: existing.id, createDocument: createDocument)
                return .downloaded
            }
        } else {
            if try await sourceRepository.existsByDisplayName(filename) {
                return .skipped
            }
        }

        try await downloadAndStore(fileInfo, from: controller, session: session, createDocument: createDocument)
        return .downloaded
    }

    private func downloadAndStore(_ fileInfo: DeviceFileInfo, from controller: any DeviceFileProvider, session: ImportSession, existingRecordingId: Int64? = nil, createDocument: Bool = true) async throws {
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

        let recordingDate = fileInfo.createdAt ?? Date()
        let deviceController = controller as? DeviceController

        // Move audio to source-organized directory if available
        let audioRelativePath: String
        if let sourceDir = deviceController?.recordingSourceDirectory {
            audioRelativePath = try fileSystemService.moveAudioToSourceDirectory(
                from: tempURL,
                filename: filename,
                sourceDirectory: sourceDir
            )
        } else {
            audioRelativePath = try fileSystemService.moveAudioToRecordings(
                from: tempURL,
                filename: filename,
                date: recordingDate
            )
        }

        // Create or update Recording entry if recording source is available
        var recordingV2Id: Int64?
        if let sourceId = deviceController?.recordingSourceId {
            if let existingId = existingRecordingId {
                // Update existing device-only record with local filepath
                try await recordingRepository.updateAfterImport(
                    id: existingId, filepath: audioRelativePath, syncStatus: .synced
                )
                recordingV2Id = existingId
            } else {
                let recording = try await recordingSourceService.createRecording(
                    filename: filename,
                    filepath: audioRelativePath,
                    sourceId: sourceId,
                    fileSizeBytes: fileInfo.size,
                    durationSeconds: fileInfo.durationSeconds,
                    deviceSerial: controller.connectionInfo?.serialNumber,
                    deviceModel: controller.connectionInfo?.model.rawValue,
                    recordingMode: fileInfo.mode,
                    syncStatus: .synced
                )
                recordingV2Id = recording.id
            }
        }

        // Create Document + Source (linked to Recording if available)
        if createDocument {
            let title = Self.documentTitle(for: recordingDate, durationSeconds: fileInfo.durationSeconds)

            do {
                let (doc, source) = try await documentService.createDocumentWithSource(
                    title: title,
                    audioRelativePath: audioRelativePath,
                    originalFilename: filename,
                    durationSeconds: fileInfo.durationSeconds,
                    fileSizeBytes: fileInfo.size,
                    deviceSerial: controller.connectionInfo?.serialNumber,
                    deviceModel: controller.connectionInfo?.model.rawValue,
                    recordingMode: fileInfo.mode?.rawValue,
                    recordedAt: recordingDate,
                    recordingId: recordingV2Id
                )
                triggerAutoTranscription(documentId: doc.id, sourceId: source.id, source: source)
            } catch {
                let audioURL = fileSystemService.dataDirectory.appendingPathComponent(audioRelativePath)
                try? FileManager.default.removeItem(at: audioURL)
                // Revert recording row if we were updating a device-only record
                if let existingId = existingRecordingId {
                    try? await recordingRepository.updateAfterImport(
                        id: existingId, filepath: "", syncStatus: .onDeviceOnly
                    )
                }
                throw error
            }
        }

        // Mark source as synced after successful import
        if let sourceId = deviceController?.recordingSourceId {
            try? await recordingSourceService.markSynced(sourceId: sourceId)
        }
    }

    // MARK: - Manual Import

    func importFiles(_ urls: [URL]) async throws -> [Document] {
        var imported: [Document] = []

        // Ensure "Imported" recording source exists
        let importSource = try await recordingSourceService.ensureImportSource()

        for url in urls {
            let filename = url.lastPathComponent

            // Skip if already exists for this source
            if try await recordingSourceService.recordingExists(filename: filename, sourceId: importSource.id) {
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

                let audioRelativePath = try fileSystemService.copyAudioToSourceDirectory(
                    from: url,
                    filename: filename,
                    sourceDirectory: importSource.directory
                )

                // Create Recording entry
                let recording = try await recordingSourceService.createRecording(
                    filename: filename,
                    filepath: audioRelativePath,
                    sourceId: importSource.id,
                    fileSizeBytes: fileSize,
                    syncStatus: .localOnly
                )

                let title = Self.documentTitle(for: creationDate, durationSeconds: nil)

                do {
                    let (doc, source) = try await documentService.createDocumentWithSource(
                        title: title,
                        audioRelativePath: audioRelativePath,
                        originalFilename: filename,
                        durationSeconds: nil,
                        fileSizeBytes: fileSize,
                        deviceSerial: nil,
                        deviceModel: nil,
                        recordingMode: nil,
                        recordedAt: creationDate,
                        recordingId: recording.id
                    )
                    imported.append(doc)
                    triggerAutoTranscription(documentId: doc.id, sourceId: source.id, source: source)
                } catch {
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

    // MARK: - Auto-Transcription

    /// Public entry point for triggering auto-transcription from external callers
    /// (e.g. manual "Create Document" flows). Fire-and-forget via Task.detached internally.
    func autoTranscribe(documentId: Int64, sourceId: Int64, source: Source) {
        triggerAutoTranscription(documentId: documentId, sourceId: sourceId, source: source)
    }

    private static let autoTranscriptionCount = 3

    private func triggerAutoTranscription(documentId: Int64, sourceId: Int64, source: Source) {
        Task.detached { [self] in
            await self.performAutoTranscription(documentId: documentId, sourceId: sourceId, source: source)
        }
    }

    private func performAutoTranscription(documentId: Int64, sourceId: Int64, source: Source) async {
        // Get transcription settings
        let settings = await MainActor.run { settingsService.settings.llm }
        let providerString = settings.defaultTranscriptionProvider
        guard let provider = LLMProvider(rawValue: providerString) else {
            AppLogger.llm.warning("No transcription provider configured, skipping auto-transcription for document \(documentId)")
            return
        }
        guard !settings.defaultTranscriptionModel.isEmpty else {
            AppLogger.llm.warning("No transcription model configured, skipping auto-transcription for document \(documentId)")
            return
        }
        let model = settings.defaultTranscriptionModel
        let count = Self.autoTranscriptionCount

        // Check if accounts are configured for the provider
        guard await llmService.hasActiveAccounts(for: provider) else {
            AppLogger.llm.warning("No \(provider.rawValue) accounts configured, skipping auto-transcription for document \(documentId)")
            return
        }

        // Collect audio relative paths (not loading data)
        var audioRelativePaths: [String] = []
        if let dbPath = source.audioPath {
            audioRelativePaths.append(dbPath)
        } else if let yamlPath = fileSystemService.readSourceAudioPath(sourceDiskPath: source.diskPath) {
            audioRelativePaths.append(yamlPath)
        } else {
            AppLogger.llm.error("Source \(source.id) has no audio path, skipping auto-transcription")
            return
        }

        // Create transcript stubs with .transcribing status
        var transcriptIds: [Int64] = []
        for index in 0..<count {
            let title = count > 1 ? "AI Transcript \(index + 1)" : "AI Transcript"
            let transcript = Transcript(
                sourceId: sourceId,
                documentId: documentId,
                title: title,
                fullText: nil,
                status: .transcribing
            )
            do {
                let inserted = try await transcriptRepository.insert(transcript, skipAutoPrimary: count > 1)
                transcriptIds.append(inserted.id)
            } catch {
                AppLogger.llm.error("Failed to create transcript stub for document \(documentId): \(error.localizedDescription)")
            }
        }

        guard !transcriptIds.isEmpty else { return }

        AppLogger.llm.info("Starting auto-transcription for document \(documentId): \(transcriptIds.count) variants")

        // Enqueue transcription jobs for each transcript
        do {
            for transcriptId in transcriptIds {
                _ = try await llmQueueService.enqueueTranscription(
                    documentId: documentId,
                    sourceId: sourceId,
                    transcriptId: transcriptId,
                    provider: provider,
                    model: model,
                    audioRelativePaths: audioRelativePaths,
                    priority: 0
                )
            }
            AppLogger.llm.info("Enqueued \(transcriptIds.count) auto-transcription job(s) for document \(documentId)")
        } catch {
            AppLogger.llm.error("Failed to enqueue auto-transcription jobs for document \(documentId): \(error.localizedDescription)")
        }

        // Note: The queue processor will handle:
        // - Generating transcripts and updating records
        // - Auto-enqueuing judge job when all transcripts complete
        // - Setting primary transcript after judge completes
        // - Writing document body
    }
}

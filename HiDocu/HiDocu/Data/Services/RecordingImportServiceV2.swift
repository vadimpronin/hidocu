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
    private let transcriptRepository: any TranscriptRepository
    private let llmService: LLMService

    init(
        fileSystemService: FileSystemService,
        documentService: DocumentService,
        sourceRepository: any SourceRepository,
        transcriptRepository: any TranscriptRepository,
        llmService: LLMService
    ) {
        self.fileSystemService = fileSystemService
        self.documentService = documentService
        self.sourceRepository = sourceRepository
        self.transcriptRepository = transcriptRepository
        self.llmService = llmService
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
            let (doc, source) = try await documentService.createDocumentWithSource(
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
            triggerAutoTranscription(documentId: doc.id, sourceId: source.id, source: source)
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
                    let (doc, source) = try await documentService.createDocumentWithSource(
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
                    triggerAutoTranscription(documentId: doc.id, sourceId: source.id, source: source)
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

    // MARK: - Auto-Transcription

    private static let autoTranscriptionModel = "gemini-3-pro-preview"
    private static let autoTranscriptionCount = 3

    private func triggerAutoTranscription(documentId: Int64, sourceId: Int64, source: Source) {
        Task.detached { [self] in
            await self.performAutoTranscription(documentId: documentId, sourceId: sourceId, source: source)
        }
    }

    private func performAutoTranscription(documentId: Int64, sourceId: Int64, source: Source) async {
        let model = Self.autoTranscriptionModel
        let count = Self.autoTranscriptionCount

        // Check if Gemini accounts are configured
        guard await llmService.hasActiveAccounts(for: .gemini) else {
            AppLogger.llm.warning("No Gemini accounts configured, skipping auto-transcription for document \(documentId)")
            return
        }

        // Prepare audio attachments
        let attachments: [LLMAttachment]
        do {
            attachments = try await llmService.prepareAudioAttachments(sources: [source], fileSystemService: fileSystemService)
        } catch {
            AppLogger.llm.error("Failed to prepare audio for auto-transcription of document \(documentId): \(error.localizedDescription)")
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
                let inserted = try await transcriptRepository.insert(transcript)
                transcriptIds.append(inserted.id)
            } catch {
                AppLogger.llm.error("Failed to create transcript stub for document \(documentId): \(error.localizedDescription)")
            }
        }

        guard !transcriptIds.isEmpty else { return }

        AppLogger.llm.info("Starting auto-transcription for document \(documentId): \(transcriptIds.count) variants")

        // Generate transcripts in parallel, collect all results
        var successfulTranscripts: [(id: Int64, text: String)] = []

        await withTaskGroup(of: (Int64, Result<String, Error>).self) { group in
            for transcriptId in transcriptIds {
                group.addTask {
                    do {
                        let text = try await self.llmService.generateSingleTranscript(
                            attachments: attachments,
                            model: model,
                            transcriptId: transcriptId,
                            documentId: documentId,
                            sourceId: sourceId
                        )
                        return (transcriptId, .success(text))
                    } catch {
                        return (transcriptId, .failure(error))
                    }
                }
            }

            for await (transcriptId, result) in group {
                do {
                    guard var transcript = try await transcriptRepository.fetchById(transcriptId) else {
                        AppLogger.llm.warning("Transcript \(transcriptId) deleted during generation")
                        continue
                    }

                    switch result {
                    case .success(let text):
                        transcript.fullText = text
                        transcript.status = .ready
                        transcript.modifiedAt = Date()
                        try await transcriptRepository.update(transcript)
                        successfulTranscripts.append((id: transcriptId, text: text))

                    case .failure(let error):
                        transcript.status = .failed
                        transcript.modifiedAt = Date()
                        try await transcriptRepository.update(transcript)
                        AppLogger.llm.error("Auto-transcription failed for transcript \(transcriptId): \(error.localizedDescription)")
                    }
                } catch {
                    AppLogger.llm.error("Failed to update transcript \(transcriptId) after generation: \(error.localizedDescription)")
                }
            }
        }

        // Select primary transcript
        guard !successfulTranscripts.isEmpty else {
            AppLogger.llm.warning("All auto-transcripts failed for document \(documentId), body remains empty")
            return
        }

        let primaryId: Int64
        let primaryText: String

        if successfulTranscripts.count == 1 {
            // Single success — set as primary directly (can't judge)
            primaryId = successfulTranscripts[0].id
            primaryText = successfulTranscripts[0].text
            AppLogger.llm.info("Single transcript \(primaryId) set as primary for document \(documentId) (no judge needed)")
        } else {
            // 2+ successes — invoke the LLM judge
            do {
                var readyTranscripts: [Transcript] = []
                for st in successfulTranscripts {
                    if let t = try await transcriptRepository.fetchById(st.id) {
                        readyTranscripts.append(t)
                    }
                }

                let judgeResponse = try await llmService.evaluateTranscripts(
                    transcripts: readyTranscripts,
                    documentId: documentId
                )

                // Validate bestId is in our set
                if let best = successfulTranscripts.first(where: { $0.id == judgeResponse.bestId }) {
                    primaryId = best.id
                    primaryText = best.text
                    AppLogger.llm.info("Judge selected transcript \(primaryId) as best for document \(documentId)")
                } else {
                    // bestId mismatch — fallback to first by ID
                    let fallback = successfulTranscripts.sorted(by: { $0.id < $1.id })[0]
                    primaryId = fallback.id
                    primaryText = fallback.text
                    AppLogger.llm.warning("Judge returned bestId=\(judgeResponse.bestId) not in transcript set, falling back to \(primaryId)")
                }
            } catch {
                // Judge failed — fallback to first transcript by ID
                let fallback = successfulTranscripts.sorted(by: { $0.id < $1.id })[0]
                primaryId = fallback.id
                primaryText = fallback.text
                AppLogger.llm.error("Judge evaluation failed for document \(documentId): \(error.localizedDescription), falling back to transcript \(primaryId)")
            }
        }

        // Commit primary and write body
        do {
            try await transcriptRepository.setPrimaryForDocument(id: primaryId, documentId: documentId)
            try await documentService.writeBodyById(documentId: documentId, content: primaryText)
            AppLogger.llm.info("Primary transcript \(primaryId) set for document \(documentId), body updated")
        } catch {
            AppLogger.llm.error("Failed to set primary transcript for document \(documentId): \(error.localizedDescription)")
        }

        // Trigger summary generation in background
        do {
            if let doc = try await documentService.fetchDocument(id: documentId) {
                Task {
                    do {
                        _ = try await self.llmService.generateSummary(for: doc)
                    } catch {
                        AppLogger.llm.error("Auto-summary generation failed for document \(documentId): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            AppLogger.llm.error("Failed to fetch document \(documentId) for summary generation: \(error.localizedDescription)")
        }

        AppLogger.llm.info("Auto-transcription completed for document \(documentId)")
    }
}

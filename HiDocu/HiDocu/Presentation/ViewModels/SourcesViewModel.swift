//
//  SourcesViewModel.swift
//  HiDocu
//
//  ViewModel for sources and transcripts management within a document.
//

import Foundation

struct SourceWithDetails: Identifiable {
    let source: Source
    let recording: RecordingV2?
    var transcripts: [Transcript]

    var id: Int64 { source.id }
}

@Observable
@MainActor
final class SourcesViewModel {

    var sources: [SourceWithDetails] = []
    var documentTranscripts: [Transcript] = []
    var isLoading = false
    var generationError: String?
    var showGenerateSheet = false
    var isJudging = false
    private var activeTranscriptIds: Set<Int64> = []

    var isGeneratingTranscripts: Bool {
        documentTranscripts.contains { $0.status == .transcribing }
    }

    var totalDurationSeconds: Int {
        sources.compactMap { $0.recording?.durationSeconds }.reduce(0, +)
    }

    private let documentService: DocumentService
    private let sourceRepository: any SourceRepository
    private let transcriptRepository: any TranscriptRepository
    private let apiLogRepository: any APILogRepository
    let recordingRepository: any RecordingRepositoryV2

    init(
        documentService: DocumentService,
        sourceRepository: any SourceRepository,
        transcriptRepository: any TranscriptRepository,
        apiLogRepository: any APILogRepository,
        recordingRepositoryV2: any RecordingRepositoryV2
    ) {
        self.documentService = documentService
        self.sourceRepository = sourceRepository
        self.transcriptRepository = transcriptRepository
        self.apiLogRepository = apiLogRepository
        self.recordingRepository = recordingRepositoryV2
    }

    func loadSources(documentId: Int64) async {
        isLoading = true
        sources.removeAll()
        defer { isLoading = false }

        do {
            let rawSources = try await sourceRepository.fetchForDocument(documentId)
            var details: [SourceWithDetails] = []

            for source in rawSources {
                let recording: RecordingV2?
                if let recId = source.recordingId {
                    recording = try await recordingRepository.fetchById(recId)
                } else {
                    recording = nil
                }
                let transcripts = try await transcriptRepository.fetchForSource(source.id)
                details.append(SourceWithDetails(
                    source: source,
                    recording: recording,
                    transcripts: transcripts
                ))
            }

            sources = details
        } catch {
            AppLogger.general.error("Failed to load sources: \(error.localizedDescription)")
        }
    }

    func addSource(documentId: Int64, recordingId: Int64, displayName: String?) async {
        do {
            _ = try await documentService.addSource(
                documentId: documentId,
                recordingId: recordingId,
                displayName: displayName
            )
            await loadSources(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to add source: \(error.localizedDescription)")
        }
    }

    func removeSource(sourceId: Int64, documentId: Int64) async {
        do {
            try await documentService.removeSource(id: sourceId)
            await loadSources(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to remove source: \(error.localizedDescription)")
        }
    }

    func addTranscript(sourceId: Int64, text: String, title: String?, documentId: Int64) async {
        do {
            let transcript = Transcript(
                sourceId: sourceId,
                title: title,
                fullText: text
            )
            _ = try await transcriptRepository.insert(transcript)
            await loadSources(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to add transcript: \(error.localizedDescription)")
        }
    }

    func deleteTranscript(id: Int64, documentId: Int64) async {
        do {
            try await transcriptRepository.delete(id: id)
            await loadSources(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to delete transcript: \(error.localizedDescription)")
        }
    }

    func updateTranscriptText(id: Int64, text: String, documentId: Int64) async {
        do {
            guard var transcript = try await transcriptRepository.fetchById(id) else { return }
            transcript.fullText = text
            transcript.modifiedAt = Date()
            try await transcriptRepository.update(transcript)
        } catch {
            AppLogger.general.error("Failed to update transcript: \(error.localizedDescription)")
        }
    }

    func setPrimary(transcriptId: Int64, sourceId: Int64, documentId: Int64) async {
        do {
            try await transcriptRepository.setPrimary(id: transcriptId, sourceId: sourceId)
            // Copy primary transcript text to document body
            if let transcript = try await transcriptRepository.fetchById(transcriptId),
               let text = transcript.fullText {
                try await documentService.writeBodyById(documentId: documentId, content: text)
            }
            await loadSources(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to set primary: \(error.localizedDescription)")
        }
    }

    // MARK: - Document-Level Transcripts

    func loadDocumentTranscripts(documentId: Int64) async {
        documentTranscripts.removeAll()
        do {
            var transcripts = try await transcriptRepository.fetchForDocument(documentId)

            // Mark stale .transcribing transcripts as .failed (app restart during generation).
            // Skip actively generating ones (tracked in activeTranscriptIds) and
            // recently created ones (likely auto-transcription in progress from import).
            let staleThreshold: TimeInterval = 1800 // 30 minutes
            for i in transcripts.indices where transcripts[i].status == .transcribing {
                guard !activeTranscriptIds.contains(transcripts[i].id) else { continue }
                let age = Date().timeIntervalSince(transcripts[i].createdAt)
                guard age > staleThreshold else { continue }
                var transcript = transcripts[i]
                transcript.status = .failed
                try await transcriptRepository.update(transcript)
                transcripts[i] = transcript
            }

            documentTranscripts = transcripts
        } catch {
            AppLogger.general.error("Failed to load document transcripts: \(error.localizedDescription)")
        }
    }

    func addDocumentTranscript(documentId: Int64, text: String, title: String?) async {
        do {
            guard let firstSourceId = sources.first?.source.id else {
                AppLogger.general.error("Cannot add transcript: no sources exist for document \(documentId)")
                return
            }
            let transcript = Transcript(
                sourceId: firstSourceId,
                documentId: documentId,
                title: title,
                fullText: text
            )
            _ = try await transcriptRepository.insert(transcript)
            await loadDocumentTranscripts(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to add document transcript: \(error.localizedDescription)")
        }
    }

    func deleteDocumentTranscript(id: Int64, documentId: Int64) async {
        do {
            try await transcriptRepository.delete(id: id)
            await loadDocumentTranscripts(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to delete document transcript: \(error.localizedDescription)")
        }
    }

    func updateDocumentTranscriptText(id: Int64, text: String) async {
        do {
            guard var transcript = try await transcriptRepository.fetchById(id) else { return }
            transcript.fullText = text
            transcript.modifiedAt = Date()
            try await transcriptRepository.update(transcript)
        } catch {
            AppLogger.general.error("Failed to update document transcript: \(error.localizedDescription)")
        }
    }

    func setDocumentPrimary(transcriptId: Int64, documentId: Int64) async {
        do {
            try await transcriptRepository.setPrimaryForDocument(id: transcriptId, documentId: documentId)
            // Copy primary transcript text to document body
            if let transcript = try await transcriptRepository.fetchById(transcriptId),
               let text = transcript.fullText {
                try await documentService.writeBodyById(documentId: documentId, content: text)
            }
            await loadDocumentTranscripts(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to set document primary: \(error.localizedDescription)")
        }
    }

    // MARK: - LLM Judge

    func judgeTranscripts(documentId: Int64, llmQueueService: LLMQueueService, provider: LLMProvider, model: String) async {
        let readyTranscripts = documentTranscripts.filter { $0.status == .ready }
        guard readyTranscripts.count >= 2 else { return }

        isJudging = true
        defer { isJudging = false }

        do {
            let transcriptIds = readyTranscripts.map(\.id)
            _ = try await llmQueueService.enqueueJudge(
                documentId: documentId,
                transcriptIds: transcriptIds,
                provider: provider,
                model: model,
                priority: 0
            )
            AppLogger.llm.info("Enqueued judge job for document \(documentId)")
            // Note: The queue processor will handle setting primary transcript
        } catch {
            AppLogger.llm.error("Failed to enqueue judge job: \(error.localizedDescription)")
            generationError = "Failed to enqueue judge job: \(error.localizedDescription)"
        }
    }

    // MARK: - AI Transcript Generation

    func generateTranscripts(
        documentId: Int64,
        model: String,
        count: Int,
        llmQueueService: LLMQueueService,
        fileSystemService: FileSystemService,
        provider: LLMProvider
    ) async {
        guard !sources.isEmpty else {
            generationError = "No audio sources available for transcription"
            return
        }

        guard let firstSourceId = sources.first?.source.id else {
            generationError = "Cannot generate transcripts: no sources exist for document \(documentId)"
            return
        }

        generationError = nil

        // Step 1: Collect audio relative paths (not loading data)
        var audioRelativePaths: [String] = []
        for sourceDetail in sources {
            let source = sourceDetail.source
            // Resolve audio path: DB audioPath → RecordingV2 filepath → source.yaml fallback
            if let dbPath = source.audioPath {
                audioRelativePaths.append(dbPath)
            } else if let recording = sourceDetail.recording {
                audioRelativePaths.append(recording.filepath)
            } else if let yamlPath = fileSystemService.readSourceAudioPath(sourceDiskPath: source.diskPath) {
                audioRelativePaths.append(yamlPath)
            } else {
                AppLogger.general.warning("Source \(source.id) has no audio path, skipping")
            }
        }

        guard !audioRelativePaths.isEmpty else {
            generationError = "No audio files found in sources"
            return
        }

        // Step 2: Pre-create transcripts with .transcribing status
        var transcriptIds: [Int64] = []
        do {
            for index in 0..<count {
                let title = count > 1 ? "AI Transcript \(index + 1)" : "AI Transcript"
                let transcript = Transcript(
                    sourceId: firstSourceId,
                    documentId: documentId,
                    title: title,
                    fullText: nil,
                    status: .transcribing
                )
                let inserted = try await transcriptRepository.insert(transcript)
                transcriptIds.append(inserted.id)
            }

            // Track active transcript IDs so loadDocumentTranscripts won't mark them as stale
            activeTranscriptIds.formUnion(transcriptIds)

            // Reload transcripts so pills appear with spinner
            await loadDocumentTranscripts(documentId: documentId)
        } catch {
            AppLogger.general.error("Failed to create transcript records: \(error.localizedDescription)")
            generationError = error.localizedDescription
            return
        }

        // Step 3: Enqueue transcription jobs for each transcript
        do {
            for transcriptId in transcriptIds {
                _ = try await llmQueueService.enqueueTranscription(
                    documentId: documentId,
                    sourceId: firstSourceId,
                    transcriptId: transcriptId,
                    provider: provider,
                    model: model,
                    audioRelativePaths: audioRelativePaths,
                    priority: 0
                )
            }
            AppLogger.general.info("Enqueued \(transcriptIds.count) transcription job(s) for document \(documentId)")
        } catch {
            AppLogger.general.error("Failed to enqueue transcription jobs: \(error.localizedDescription)")
            generationError = error.localizedDescription
        }

        // Note: The queue processor will handle updating transcript records with results
        // and triggering judge evaluation when all transcripts are complete.
        // UI will observe status changes via loadDocumentTranscripts().
    }

    /// Fetches the error message for a failed transcript from API logs.
    func fetchTranscriptError(transcriptId: Int64) async -> String? {
        do {
            guard let logEntry = try await apiLogRepository.fetchLatestForTranscript(transcriptId: transcriptId) else {
                return nil
            }

            if logEntry.status == "error" || logEntry.status == "rate_limited" {
                return logEntry.error
            }
            return nil
        } catch {
            AppLogger.general.error("Failed to fetch transcript error: \(error.localizedDescription)")
            return nil
        }
    }
}

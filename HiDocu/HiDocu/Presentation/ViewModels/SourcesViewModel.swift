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

    var totalDurationSeconds: Int {
        sources.compactMap { $0.recording?.durationSeconds }.reduce(0, +)
    }

    private let documentService: DocumentService
    private let sourceRepository: any SourceRepository
    private let transcriptRepository: any TranscriptRepository
    let recordingRepository: any RecordingRepositoryV2

    init(
        documentService: DocumentService,
        sourceRepository: any SourceRepository,
        transcriptRepository: any TranscriptRepository,
        recordingRepositoryV2: any RecordingRepositoryV2
    ) {
        self.documentService = documentService
        self.sourceRepository = sourceRepository
        self.transcriptRepository = transcriptRepository
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
            documentTranscripts = try await transcriptRepository.fetchForDocument(documentId)
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
        guard documentTranscripts.count > 1 else { return }
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
}

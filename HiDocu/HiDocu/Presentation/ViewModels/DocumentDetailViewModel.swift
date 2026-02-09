//
//  DocumentDetailViewModel.swift
//  HiDocu
//
//  ViewModel for document detail - manages body/summary editing with debounced auto-save.
//

import Foundation
import Combine
import os

@Observable
@MainActor
final class DocumentDetailViewModel {

    var document: Document?
    var titleText: String = ""
    var bodyText: String = ""
    var summaryText: String = ""
    var titleModified = false
    var bodyModified = false
    var summaryModified = false
    var selectedTab: DetailTab = .body
    var isSaving = false
    var bodyBytes: Int = 0
    var summaryBytes: Int = 0
    var errorMessage: String?
    var summaryGenerationState: ContentGenerationState = .idle
    var bodyGenerationState: ContentGenerationState = .idle
    var isSummaryEditing: Bool = false
    var isBodyEditing: Bool = false
    var selectedModelId: String = ""

    enum DetailTab: String, CaseIterable {
        case body = "Body"
        case summary = "Summary"
        case sources = "Sources"
        case info = "Info"
    }

    enum ContentGenerationState: Equatable {
        case idle
        case generating
        case error(String)
    }

    private let documentService: DocumentService
    private let llmService: LLMService?
    private let llmQueueService: LLMQueueService?
    private let settingsService: SettingsService
    @ObservationIgnored
    private var loadedTitle = ""
    @ObservationIgnored
    private var loadedBody = ""
    @ObservationIgnored
    private var loadedSummary = ""
    @ObservationIgnored
    nonisolated(unsafe) private var saveTimer: Timer?
    @ObservationIgnored
    private var summaryGenerationTask: Task<Void, Never>?
    @ObservationIgnored
    private var bodyGenerationTask: Task<Void, Never>?

    init(documentService: DocumentService, llmService: LLMService? = nil, llmQueueService: LLMQueueService? = nil, settingsService: SettingsService) {
        self.documentService = documentService
        self.llmService = llmService
        self.llmQueueService = llmQueueService
        self.settingsService = settingsService
    }

    func loadDocument(_ doc: Document) {
        // Cancel any previous generation polling
        bodyGenerationTask?.cancel()
        bodyGenerationTask = nil
        bodyGenerationState = .idle
        summaryGenerationTask?.cancel()
        summaryGenerationTask = nil
        summaryGenerationState = .idle

        document = doc
        titleText = doc.title
        loadedTitle = doc.title
        do {
            bodyText = try documentService.readBody(diskPath: doc.diskPath)
            summaryText = try documentService.readSummary(diskPath: doc.diskPath)
        } catch {
            errorMessage = "Failed to load document: \(error.localizedDescription)"
        }
        loadedBody = bodyText
        loadedSummary = summaryText
        titleModified = false
        bodyModified = false
        summaryModified = false
        isBodyEditing = false
        isSummaryEditing = false
        updateByteCounts()

        // Determine initial model selection
        if let docModel = doc.summaryModel, !docModel.isEmpty {
            selectedModelId = docModel
        } else {
            let settings = settingsService.settings.llm
            let defaultModel = settings.defaultModel
            let defaultProvider = settings.defaultProvider
            if !defaultModel.isEmpty {
                selectedModelId = "\(defaultProvider):\(defaultModel)"
            } else {
                selectedModelId = ""
            }
        }

        // Check if a summary job is already in progress from a previous session
        checkPendingSummaryJob()
        checkPendingBodyJobs()
    }

    func reloadBody() {
        guard let doc = document else { return }
        do {
            bodyText = try documentService.readBody(diskPath: doc.diskPath)
            loadedBody = bodyText
            bodyModified = false
            updateByteCounts()
        } catch {
            errorMessage = "Failed to reload body: \(error.localizedDescription)"
        }
    }

    func titleDidChange() {
        let modified = titleText != loadedTitle
        titleModified = modified
        if modified { scheduleSave() }
    }

    func bodyDidChange() {
        let modified = bodyText != loadedBody
        bodyModified = modified
        updateByteCounts()
        if modified { scheduleSave() }
    }

    func summaryDidChange() {
        guard summaryGenerationState != .generating else { return }
        let modified = summaryText != loadedSummary
        summaryModified = modified
        updateByteCounts()
        if modified { scheduleSave() }
    }

    func saveIfNeeded() async {
        guard let doc = document else { return }
        guard titleModified || bodyModified || summaryModified else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            if titleModified, document != nil {
                try await documentService.updateTitle(id: doc.id, newTitle: titleText)
                loadedTitle = titleText
                titleModified = false
            }
            if bodyModified, document != nil {
                try await documentService.writeBody(documentId: doc.id, diskPath: doc.diskPath, content: bodyText)
                loadedBody = bodyText
                bodyModified = false
            }
            if summaryModified, document != nil {
                try await documentService.writeSummary(documentId: doc.id, diskPath: doc.diskPath, content: summaryText)
                loadedSummary = summaryText
                summaryModified = false
                if let refreshed = try await documentService.fetchDocument(id: doc.id) {
                    document = refreshed
                }
            }
        } catch {
            // Silently ignore save errors if document was cleared (e.g., deleted)
            guard document != nil else { return }
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    /// Perform physical disk rename if title has changed since the last disk sync.
    /// Call when switching documents or dismissing the view.
    func flushDiskRename() async {
        guard let doc = document else { return }
        do {
            try await documentService.renameDocumentOnDisk(id: doc.id)
            // Refresh document to get updated diskPath
            if let refreshed = try await documentService.fetchDocument(id: doc.id) {
                document = refreshed
            }
        } catch {
            AppLogger.fileSystem.error("Failed to rename document on disk: \(error.localizedDescription)")
        }
    }

    /// Cancel any pending save and clear modified flags.
    /// Call before deleting the current document to prevent race conditions.
    func cancelPendingSave() {
        saveTimer?.invalidate()
        saveTimer = nil
        titleModified = false
        bodyModified = false
        summaryModified = false
        document = nil
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.saveIfNeeded()
            }
        }
    }

    private func updateByteCounts() {
        bodyBytes = bodyText.utf8.count
        summaryBytes = summaryText.utf8.count
    }

    var hasLLMService: Bool { llmService != nil && llmQueueService != nil }

    var availableModels: [AvailableModel] {
        llmService?.availableModels ?? []
    }

    // MARK: - Summary Generation

    var hasSummary: Bool {
        !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Checks whether a summary job is already pending/running for this document
    /// and updates state accordingly. Call on view appear or document load.
    func checkPendingSummaryJob() {
        guard let doc = document, let llmQueueService else { return }
        summaryGenerationTask = Task {
            let hasPending = await llmQueueService.hasPendingSummaryJob(documentId: doc.id)
            if hasPending && summaryGenerationState != .generating {
                summaryGenerationState = .generating
                await startSummaryPolling(documentId: doc.id)
            }
        }
    }

    /// Checks whether body-producing jobs (transcription/judge) are pending for this document.
    /// Only starts polling when the body is currently empty (initial transcription).
    /// Re-transcription scenarios update body via SourcesViewModel flow.
    func checkPendingBodyJobs() {
        guard let doc = document, let llmQueueService,
              bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let initialBodyHash = doc.bodyHash
        bodyGenerationTask = Task {
            let hasPending = await llmQueueService.hasPendingBodyJob(documentId: doc.id)
            if hasPending && bodyGenerationState != .generating {
                bodyGenerationState = .generating
                await startBodyPolling(documentId: doc.id, initialBodyHash: initialBodyHash)
            }
        }
    }

    func generateSummary() {
        guard let doc = document, let llmQueueService else { return }
        saveTimer?.invalidate()
        saveTimer = nil
        summaryGenerationState = .generating
        let modelId = selectedModelId.isEmpty ? nil : selectedModelId

        // Determine provider and model
        let provider: LLMProvider
        let model: String
        if let override = modelId {
            let parts = override.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let providerValue = LLMProvider(rawValue: String(parts[0])) {
                provider = providerValue
                model = String(parts[1])
            } else {
                let settings = settingsService.settings.llm
                provider = LLMProvider(rawValue: settings.defaultProvider) ?? .claude
                model = settings.defaultModel.isEmpty ? "claude-3-5-sonnet-20241022" : settings.defaultModel
            }
        } else {
            let settings = settingsService.settings.llm
            provider = LLMProvider(rawValue: settings.defaultProvider) ?? .claude
            model = settings.defaultModel.isEmpty ? "claude-3-5-sonnet-20241022" : settings.defaultModel
        }

        summaryGenerationTask = Task {
            do {
                _ = try await llmQueueService.enqueueSummary(
                    documentId: doc.id,
                    provider: provider,
                    model: model,
                    modelOverride: modelId,
                    priority: 0
                )

                await startSummaryPolling(documentId: doc.id)
            } catch is CancellationError {
                summaryGenerationState = .idle
            } catch {
                summaryGenerationState = .error(error.localizedDescription)
            }
        }
    }

    /// Polls for summary completion, checking both the document and the job queue.
    /// Runs indefinitely until the summary appears, the job fails/cancels, or the task is cancelled.
    private func startSummaryPolling(documentId: Int64) async {
        let enqueueTime = Date()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { break }

            // Check if summary was generated
            if let refreshed = try? await documentService.fetchDocument(id: documentId),
               let summaryGenAt = refreshed.summaryGeneratedAt,
               summaryGenAt > enqueueTime {
                document = refreshed
                summaryText = (try? documentService.readSummary(diskPath: refreshed.diskPath)) ?? ""
                loadedSummary = summaryText
                summaryModified = false
                summaryGenerationState = .idle
                isSummaryEditing = false
                updateByteCounts()
                return
            }

            // Check if the job still exists and hasn't failed
            guard let llmQueueService else { break }
            let hasPending = await llmQueueService.hasPendingSummaryJob(documentId: documentId)
            if !hasPending {
                // Job is no longer pending/running - check if it failed
                // (if it completed, we would have caught it above via summaryGeneratedAt)
                summaryGenerationState = .error("Summary generation failed. Check job queue for details.")
                return
            }
        }

        // Cancelled
        if Task.isCancelled {
            summaryGenerationState = .idle
        }
    }

    /// Polls for body content completion by watching for bodyHash changes.
    private func startBodyPolling(documentId: Int64, initialBodyHash: String?) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { break }

            // Check if body was written (bodyHash changed)
            if let refreshed = try? await documentService.fetchDocument(id: documentId),
               refreshed.bodyHash != initialBodyHash, refreshed.bodyHash != nil {
                document = refreshed
                bodyText = (try? documentService.readBody(diskPath: refreshed.diskPath)) ?? ""
                loadedBody = bodyText
                bodyModified = false
                bodyGenerationState = .idle
                isBodyEditing = false
                updateByteCounts()

                // Body appeared — check if summary job was auto-enqueued after judge
                checkPendingSummaryJob()
                return
            }

            // Check if jobs still exist
            guard let llmQueueService else { break }
            let hasPending = await llmQueueService.hasPendingBodyJob(documentId: documentId)
            if !hasPending {
                bodyGenerationState = .error("Content generation failed. Check job queue for details.")
                return
            }
        }

        if Task.isCancelled {
            bodyGenerationState = .idle
        }
    }

    /// Cancels the summary generation polling (wired to summary tab Cancel button).
    func cancelGeneration() {
        summaryGenerationTask?.cancel()
        summaryGenerationTask = nil
        summaryGenerationState = .idle
    }

    deinit {
        saveTimer?.invalidate()
        summaryGenerationTask?.cancel()
        bodyGenerationTask?.cancel()
    }
}

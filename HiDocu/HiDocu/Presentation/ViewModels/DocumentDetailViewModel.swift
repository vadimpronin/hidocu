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
    var summaryGenerationState: SummaryGenerationState = .idle
    var isSummaryEditing: Bool = false
    var isBodyEditing: Bool = false
    var selectedModelId: String = ""

    enum DetailTab: String, CaseIterable {
        case body = "Body"
        case summary = "Summary"
        case sources = "Sources"
        case info = "Info"
    }

    enum SummaryGenerationState: Equatable {
        case idle
        case generating
        case error(String)
    }

    private let documentService: DocumentService
    private let llmService: LLMService?
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
    private var generationTask: Task<Void, Never>?

    init(documentService: DocumentService, llmService: LLMService? = nil, settingsService: SettingsService) {
        self.documentService = documentService
        self.llmService = llmService
        self.settingsService = settingsService
    }

    func loadDocument(_ doc: Document) {
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

    var hasLLMService: Bool { llmService != nil }

    var availableModels: [AvailableModel] {
        llmService?.availableModels ?? []
    }

    // MARK: - Summary Generation

    var hasSummary: Bool {
        !summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func generateSummary() {
        guard let doc = document, let llmService else { return }
        saveTimer?.invalidate()
        saveTimer = nil
        summaryGenerationState = .generating
        let modelId = selectedModelId.isEmpty ? nil : selectedModelId

        generationTask = Task {
            do {
                let response = try await llmService.generateSummary(for: doc, modelOverride: modelId)
                summaryText = response.content
                loadedSummary = response.content
                summaryModified = false
                summaryGenerationState = .idle
                isSummaryEditing = false
                updateByteCounts()
                if let refreshed = try await documentService.fetchDocument(id: doc.id) {
                    document = refreshed
                }
            } catch is CancellationError {
                summaryGenerationState = .idle
            } catch {
                summaryGenerationState = .error(error.localizedDescription)
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        summaryGenerationState = .idle
    }

    deinit {
        saveTimer?.invalidate()
        generationTask?.cancel()
    }
}

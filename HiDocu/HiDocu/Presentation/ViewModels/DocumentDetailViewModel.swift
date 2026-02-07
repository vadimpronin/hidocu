//
//  DocumentDetailViewModel.swift
//  HiDocu
//
//  ViewModel for document detail - manages body/summary editing with debounced auto-save.
//

import Foundation
import Combine

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

    enum DetailTab: String, CaseIterable {
        case body = "Body"
        case summary = "Summary"
        case sources = "Sources"
        case info = "Info"
    }

    private let documentService: DocumentService
    @ObservationIgnored
    private var loadedTitle = ""
    @ObservationIgnored
    private var loadedBody = ""
    @ObservationIgnored
    private var loadedSummary = ""
    @ObservationIgnored
    nonisolated(unsafe) private var saveTimer: Timer?

    init(documentService: DocumentService) {
        self.documentService = documentService
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
        updateByteCounts()
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
                try await documentService.renameDocument(id: doc.id, newTitle: titleText)
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
            }
        } catch {
            // Silently ignore save errors if document was cleared (e.g., deleted)
            guard document != nil else { return }
            errorMessage = "Failed to save: \(error.localizedDescription)"
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

    deinit {
        saveTimer?.invalidate()
    }
}

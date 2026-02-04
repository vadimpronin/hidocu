//
//  TranscriptionViewModel.swift
//  HiDocu
//
//  View model for managing transcription variants.
//

import Foundation
import AppKit

/// View model for the transcription section.
///
/// Manages:
/// - Multiple transcription variants (up to 5) per recording
/// - Auto-save on tab switch and disappear
/// - Unsaved changes tracking
/// - Export to clipboard, Markdown, and file
@Observable @MainActor
final class TranscriptionViewModel {

    // MARK: - Dependencies

    private let repository: TranscriptionRepository
    private let recordingId: Int64
    private let recordingTitle: String?

    // MARK: - State

    private(set) var variants: [Transcription] = []
    private(set) var selectedVariantId: Int64?
    var editableText: String = ""
    private(set) var hasUnsavedChanges: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var error: String?

    private var lastSavedText: String = ""

    /// Maximum allowed variants per recording
    static let maxVariants = 5

    var canAddVariant: Bool {
        variants.count < Self.maxVariants
    }

    var selectedVariant: Transcription? {
        guard let id = selectedVariantId else { return nil }
        return variants.first { $0.id == id }
    }

    // MARK: - Initialization

    init(recordingId: Int64, recordingTitle: String?, repository: TranscriptionRepository) {
        self.recordingId = recordingId
        self.recordingTitle = recordingTitle
        self.repository = repository
    }

    // MARK: - Loading

    func loadVariants() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            variants = try await repository.fetchForRecording(recordingId)

            // Select first variant (primary) if none selected, or reselect current
            if let currentId = selectedVariantId,
               variants.contains(where: { $0.id == currentId }) {
                // Keep current selection, refresh text
                if let variant = variants.first(where: { $0.id == currentId }) {
                    editableText = variant.fullText ?? ""
                    lastSavedText = editableText
                    hasUnsavedChanges = false
                }
            } else if let first = variants.first {
                selectedVariantId = first.id
                editableText = first.fullText ?? ""
                lastSavedText = editableText
                hasUnsavedChanges = false
            } else {
                selectedVariantId = nil
                editableText = ""
                lastSavedText = ""
                hasUnsavedChanges = false
            }
        } catch {
            self.error = error.localizedDescription
            AppLogger.transcription.error("Failed to load variants: \(error.localizedDescription)")
        }
    }

    // MARK: - Text Tracking

    func textDidChange() {
        hasUnsavedChanges = editableText != lastSavedText
    }

    // MARK: - Save

    func saveCurrentText() async {
        guard hasUnsavedChanges, let variantId = selectedVariantId else { return }
        guard var variant = variants.first(where: { $0.id == variantId }) else { return }

        isSaving = true
        error = nil
        defer { isSaving = false }

        do {
            variant.fullText = editableText
            try await repository.update(variant)
            lastSavedText = editableText
            hasUnsavedChanges = false

            // Update local cache
            if let index = variants.firstIndex(where: { $0.id == variantId }) {
                variants[index].fullText = editableText
            }

            AppLogger.transcription.info("Saved transcription variant \(variantId)")
        } catch {
            self.error = error.localizedDescription
            AppLogger.transcription.error("Failed to save: \(error.localizedDescription)")
        }
    }

    // MARK: - Tab Switching

    func selectVariant(id: Int64) async {
        guard id != selectedVariantId else { return }

        // Auto-save dirty text before switching
        if hasUnsavedChanges {
            await saveCurrentText()
        }

        selectedVariantId = id
        if let variant = variants.first(where: { $0.id == id }) {
            editableText = variant.fullText ?? ""
            lastSavedText = editableText
            hasUnsavedChanges = false
        }
    }

    // MARK: - Variant Operations

    func addVariant(title: String?) async {
        guard canAddVariant else { return }

        // Auto-save current before adding
        if hasUnsavedChanges {
            await saveCurrentText()
        }

        error = nil

        do {
            let transcription = Transcription(
                recordingId: recordingId,
                title: title?.isEmpty == true ? nil : title
            )
            let inserted = try await repository.insert(transcription)

            await loadVariants()

            // Select the newly added variant
            selectedVariantId = inserted.id
            editableText = inserted.fullText ?? ""
            lastSavedText = editableText
            hasUnsavedChanges = false

            AppLogger.transcription.info("Added variant: \(inserted.id)")
        } catch {
            self.error = error.localizedDescription
            AppLogger.transcription.error("Failed to add variant: \(error.localizedDescription)")
        }
    }

    func deleteVariant(id: Int64) async {
        error = nil

        do {
            try await repository.delete(id: id)
            await loadVariants()

            AppLogger.transcription.info("Deleted variant: \(id)")
        } catch {
            self.error = error.localizedDescription
            AppLogger.transcription.error("Failed to delete variant: \(error.localizedDescription)")
        }
    }

    func setPrimary(id: Int64) async {
        error = nil

        do {
            try await repository.setPrimary(id: id, recordingId: recordingId)
            await loadVariants()

            AppLogger.transcription.info("Set primary variant: \(id)")
        } catch {
            self.error = error.localizedDescription
            AppLogger.transcription.error("Failed to set primary: \(error.localizedDescription)")
        }
    }

    func renameVariant(id: Int64, newTitle: String?) async {
        guard var variant = variants.first(where: { $0.id == id }) else { return }

        error = nil

        do {
            variant.title = newTitle?.isEmpty == true ? nil : newTitle
            try await repository.update(variant)

            if let index = variants.firstIndex(where: { $0.id == id }) {
                variants[index].title = variant.title
            }

            AppLogger.transcription.info("Renamed variant \(id)")
        } catch {
            self.error = error.localizedDescription
            AppLogger.transcription.error("Failed to rename variant: \(error.localizedDescription)")
        }
    }

    // MARK: - Export

    func copyToClipboard() {
        guard let variant = selectedVariant, let text = variant.fullText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportPrimaryAsMarkdown() -> String? {
        guard let primary = variants.first(where: { $0.isPrimary }) else { return nil }
        guard let text = primary.fullText, !text.isEmpty else { return nil }

        var md = "# Transcription"
        if let title = recordingTitle {
            md += ": \(title)"
        }
        md += "\n\n"

        if let transcribedAt = primary.transcribedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            md += "**Transcribed:** \(formatter.string(from: transcribedAt))\n"
        }
        if let language = primary.language {
            md += "**Language:** \(language)\n"
        }
        if let model = primary.modelUsed {
            md += "**Model:** \(model)\n"
        }
        md += "\n---\n\n"
        md += text

        return md
    }

    func exportToFile() {
        guard let markdown = exportPrimaryAsMarkdown() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(recordingTitle ?? "transcription").md"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            AppLogger.transcription.info("Exported transcription to \(url.path)")
        } catch {
            self.error = error.localizedDescription
            AppLogger.transcription.error("Export failed: \(error.localizedDescription)")
        }
    }
}

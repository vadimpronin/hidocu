//
//  TranscriptStudioView.swift
//  HiDocu
//
//  Transcript Studio: vertical-stack layout for managing document transcripts.
//  Replaces the former SourceBrowserView with an integrated audio timeline,
//  variant tabs, promote banner, text editor, and status bar.
//

import SwiftUI

struct TranscriptStudioView: View {
    @Environment(\.container) private var container
    @Bindable var viewModel: SourcesViewModel
    let documentId: Int64
    var onBodyUpdated: (() -> Void)?

    @State private var selectedTranscriptId: Int64?
    @State private var isEditing = false
    @State private var editedText = ""
    @State private var showPromoteConfirmation = false
    @State private var showAddSheet = false
    @State private var showGenerateSheet = false
    @State private var showRecordingPicker = false
    @State private var activeSourceIndex = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var failedTranscriptError: String?

    var body: some View {
        Group {
            if viewModel.sources.isEmpty && viewModel.documentTranscripts.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                mainContent
            }
        }
        .errorBanner($viewModel.generationError)
        .task(id: ObjectIdentifier(viewModel)) {
            // Only trigger data loading. Selection is handled reactively
            // by .onChange(of: viewModel.documentTranscripts).
            await viewModel.loadSources(documentId: documentId)
            await viewModel.loadDocumentTranscripts(documentId: documentId)
        }
        .onDisappear {
            flushPendingSave(for: selectedTranscriptId)
        }
        .sheet(isPresented: $showRecordingPicker) {
            RecordingPickerView(
                documentId: documentId,
                viewModel: viewModel,
                recordingRepository: viewModel.recordingRepository
            )
        }
        .sheet(isPresented: $showAddSheet) {
            AddTranscriptSheet(documentId: documentId, viewModel: viewModel)
        }
        .sheet(isPresented: $showGenerateSheet) {
            GenerateTranscriptSheet { model, count in
                guard let container else { return }
                // Determine provider from settings (defaultTranscriptionProvider)
                let providerString = container.settingsService.settings.llm.defaultTranscriptionProvider
                let provider = LLMProvider(rawValue: providerString) ?? .gemini
                Task {
                    await viewModel.generateTranscripts(
                        documentId: documentId,
                        model: model,
                        count: count,
                        llmQueueService: container.llmQueueService,
                        fileSystemService: container.fileSystemService,
                        provider: provider
                    )
                }
            }
        }
        .confirmationDialog(
            "Replace Document Body",
            isPresented: $showPromoteConfirmation,
            presenting: selectedTranscript
        ) { transcript in
            Button("Replace Document Body") {
                promoteTranscript(transcript)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This will replace the current Document Body with this transcript. The previous body text will not be recoverable unless you have another transcript variant.")
        }
        .onChange(of: viewModel.documentTranscripts) { _, newTranscripts in
            guard !newTranscripts.isEmpty else { return }

            if selectedTranscriptId == nil {
                // Initial load — prefer .ready or .isPrimary, skip .transcribing
                let target = newTranscripts.first(where: { $0.isPrimary && $0.status == .ready })
                    ?? newTranscripts.first(where: { $0.status == .ready })
                    ?? newTranscripts.first
                if let target {
                    selectedTranscriptId = target.id
                    editedText = target.fullText ?? ""
                    isEditing = false
                }
            } else if let current = newTranscripts.first(where: { $0.id == selectedTranscriptId }) {
                // Data reloaded while we have a selection — refresh text
                // unless the user is actively editing
                if !isEditing {
                    editedText = current.fullText ?? ""
                }
                // If transcript became .failed, fetch error
                if current.status == .failed {
                    Task {
                        failedTranscriptError = await viewModel.fetchTranscriptError(transcriptId: current.id)
                    }
                }
            } else {
                // Selected transcript was deleted — fall back
                let target = newTranscripts.first(where: { $0.isPrimary && $0.status == .ready })
                    ?? newTranscripts.first(where: { $0.status == .ready })
                    ?? newTranscripts.first
                if let target {
                    selectedTranscriptId = target.id
                    editedText = target.fullText ?? ""
                    isEditing = false
                } else {
                    selectedTranscriptId = nil
                    editedText = ""
                }
            }
        }
        .onChange(of: selectedTranscriptId) { _, newId in
            // Fetch error when selecting a failed transcript
            if let newId, let transcript = viewModel.documentTranscripts.first(where: { $0.id == newId }), transcript.status == .failed {
                Task {
                    failedTranscriptError = await viewModel.fetchTranscriptError(transcriptId: newId)
                }
            } else {
                failedTranscriptError = nil
            }
        }
    }

    // MARK: - Computed Properties

    private var selectedTranscript: Transcript? {
        guard let id = selectedTranscriptId else { return nil }
        return viewModel.documentTranscripts.first { $0.id == id }
    }

    private var wordCount: Int {
        editedText.split(whereSeparator: \.isWhitespace).count
    }

    private var isTextModified: Bool {
        guard let transcript = selectedTranscript else { return false }
        return editedText != (transcript.fullText ?? "")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No Sources")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Add an audio recording to start transcribing")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Button("Add Source") {
                showRecordingPicker = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // 1. Audio Timeline
            AudioTimelineView(
                sources: viewModel.sources,
                activeSourceIndex: $activeSourceIndex,
                onAddSource: { showRecordingPicker = true },
                onRemoveSource: { sourceId in
                    Task {
                        await viewModel.removeSource(sourceId: sourceId, documentId: documentId)
                    }
                }
            )

            Divider()

            // 2. Variant Tab Bar
            VariantTabBar(
                transcripts: viewModel.documentTranscripts,
                selectedId: $selectedTranscriptId,
                onAdd: { showAddSheet = true },
                onDelete: { transcriptId in
                    Task {
                        let wasSelected = selectedTranscriptId == transcriptId
                        await viewModel.deleteDocumentTranscript(id: transcriptId, documentId: documentId)
                        if wasSelected {
                            if let first = viewModel.documentTranscripts.first {
                                selectTranscript(first)
                            }
                        }
                    }
                },
                onPromote: { transcriptId in
                    selectedTranscriptId = transcriptId
                    showPromoteConfirmation = true
                },
                onGenerate: { showGenerateSheet = true },
                onJudge: {
                    guard let container else { return }
                    // Determine provider and model from settings (defaultJudgeProvider/Model)
                    let settings = container.settingsService.settings.llm
                    let providerString = settings.defaultJudgeProvider
                    let provider = LLMProvider(rawValue: providerString) ?? .gemini
                    let model = settings.defaultJudgeModel.isEmpty ? "gemini-3-pro-preview" : settings.defaultJudgeModel
                    Task {
                        await viewModel.judgeTranscripts(
                            documentId: documentId,
                            llmQueueService: container.llmQueueService,
                            provider: provider,
                            model: model
                        )
                    }
                },
                isGenerating: viewModel.isGeneratingTranscripts,
                isJudging: viewModel.isJudging
            )

            Divider()

            // 3-6. Editor area with promote banner and status bar
            if let transcript = selectedTranscript {
                // Status-aware rendering
                switch transcript.status {
                case .transcribing:
                    generatingPlaceholder
                case .failed:
                    failedTranscriptView(transcript)
                case .ready:
                    editorArea
                }
            } else {
                emptyTranscriptState
            }
        }
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        VStack(spacing: 0) {
            ScrollView {
                MarkdownEditableView(
                    text: $editedText,
                    isEditing: $isEditing,
                    placeholder: "No transcript"
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                // 3. Promote Banner (conditional)
                if let transcript = selectedTranscript, !transcript.isPrimary {
                    PromoteBanner {
                        showPromoteConfirmation = true
                    }
                }
            }
            .onChange(of: editedText) { _, _ in
                if isTextModified {
                    scheduleSave()
                }
            }
            .onChange(of: selectedTranscriptId) { oldId, newId in
                // Flush pending save for the previous variant before switching
                flushPendingSave(for: oldId)
                // Update editor text for the new variant (user-initiated tab switch)
                guard let newId else { return }
                if let transcript = viewModel.documentTranscripts.first(where: { $0.id == newId }) {
                    editedText = transcript.fullText ?? ""
                    isEditing = false
                }
            }

            Divider()

            // 5. Status Bar
            TranscriptStatusBar(
                isModified: isTextModified,
                wordCount: wordCount,
                isEditing: $isEditing
            )
        }
    }

    // MARK: - Generating Placeholder

    private var generatingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Generating transcript...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This may take several minutes for long recordings")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Failed Transcript View

    private func failedTranscriptView(_ transcript: Transcript) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Transcript Generation Failed")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let errorMessage = failedTranscriptError {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: 12) {
                Button("Delete") {
                    Task {
                        await viewModel.deleteDocumentTranscript(id: transcript.id, documentId: documentId)
                    }
                }
                .buttonStyle(.bordered)

                Button("Retry") {
                    // TODO: Implement retry logic
                }
                .buttonStyle(.borderedProminent)
                .disabled(true) // Disable for now
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty Transcript State

    private var emptyTranscriptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No transcripts")
                .font(.title3)
                .foregroundStyle(.tertiary)

            Text("Add a transcript variant to get started")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Button("Add Variant") {
                showAddSheet = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func selectTranscript(_ transcript: Transcript) {
        // editedText and isEditing are set by onChange(of: selectedTranscriptId)
        selectedTranscriptId = transcript.id
    }

    private func promoteTranscript(_ transcript: Transcript) {
        Task {
            await viewModel.setDocumentPrimary(
                transcriptId: transcript.id,
                documentId: documentId
            )
            onBodyUpdated?()
        }
    }

    private func scheduleSave() {
        guard let transcriptId = selectedTranscriptId else { return }
        let textSnapshot = editedText
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await viewModel.updateDocumentTranscriptText(
                id: transcriptId,
                text: textSnapshot
            )
        }
    }

    private func flushPendingSave(for transcriptId: Int64?) {
        guard let transcriptId else { return }
        saveTask?.cancel()
        // Save immediately if there are unsaved changes.
        // Store in saveTask so it remains trackable/cancellable.
        let currentText = editedText
        if let transcript = viewModel.documentTranscripts.first(where: { $0.id == transcriptId }),
           currentText != (transcript.fullText ?? "") {
            saveTask = Task {
                await viewModel.updateDocumentTranscriptText(
                    id: transcriptId,
                    text: currentText
                )
            }
        } else {
            saveTask = nil
        }
    }
}

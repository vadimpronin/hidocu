//
//  SourceBrowserView.swift
//  HiDocu
//
//  Master-detail split view for transcript management and preview.
//

import SwiftUI

struct SourceBrowserView: View {
    @Bindable var viewModel: SourcesViewModel
    let documentId: Int64
    var onBodyUpdated: (() -> Void)?

    @State private var selectedTranscriptId: Int64?
    @State private var showRecordingPicker = false
    @State private var addTranscriptSourceId: Int64?
    @State private var showPromoteConfirmation = false

    var body: some View {
        Group {
            if viewModel.sources.isEmpty && !viewModel.isLoading {
                emptyStateNoSources
            } else {
                // HSplitView is used instead of NavigationSplitView because this view
                // is already nested inside the app's 3-column NavigationSplitView
                // (ContentViewV2). Nesting another NavigationSplitView causes layout
                // conflicts and double-navigation chrome.
                HSplitView {
                    sourceNavigator
                    contentInspector
                }
            }
        }
        .task {
            await viewModel.loadSources(documentId: documentId)
        }
        .sheet(isPresented: $showRecordingPicker) {
            RecordingPickerView(
                documentId: documentId,
                viewModel: viewModel,
                recordingRepository: viewModel.recordingRepository
            )
        }
        .sheet(isPresented: Binding(
            get: { addTranscriptSourceId != nil },
            set: { if !$0 { addTranscriptSourceId = nil } }
        )) {
            if let sourceId = addTranscriptSourceId {
                AddTranscriptSheet(
                    sourceId: sourceId,
                    documentId: documentId,
                    viewModel: viewModel
                )
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
    }

    // MARK: - Computed Properties

    private var selectedSourceId: Int64? {
        guard let transcriptId = selectedTranscriptId else { return nil }
        return viewModel.sources.first { detail in
            detail.transcripts.contains { $0.id == transcriptId }
        }?.source.id
    }

    private var selectedTranscript: Transcript? {
        guard let transcriptId = selectedTranscriptId else { return nil }
        for detail in viewModel.sources {
            if let transcript = detail.transcripts.first(where: { $0.id == transcriptId }) {
                return transcript
            }
        }
        return nil
    }

    private var selectedRecording: RecordingV2? {
        guard let sourceId = selectedSourceId else { return nil }
        return viewModel.sources.first { $0.source.id == sourceId }?.recording
    }

    // MARK: - Empty State (No Sources)

    private var emptyStateNoSources: some View {
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

    // MARK: - Source Navigator (Left Pane)

    private var sourceNavigator: some View {
        VStack(spacing: 0) {
            navigatorHeaderBar

            Divider()

            List(selection: $selectedTranscriptId) {
                ForEach(viewModel.sources) { detail in
                    Section {
                        ForEach(detail.transcripts) { transcript in
                            TranscriptNavigatorRow(transcript: transcript)
                                .tag(transcript.id)
                                .contextMenu {
                                    Button("Use as Document Body") {
                                        selectedTranscriptId = transcript.id
                                        showPromoteConfirmation = true
                                    }
                                    .disabled(transcript.isPrimary)

                                    Divider()

                                    Button("Delete Transcript", role: .destructive) {
                                        Task {
                                            await viewModel.deleteTranscript(
                                                id: transcript.id,
                                                documentId: documentId
                                            )
                                            if selectedTranscriptId == transcript.id {
                                                selectedTranscriptId = nil
                                            }
                                        }
                                    }
                                }
                        }
                    } header: {
                        SourceSectionHeader(detail: detail)
                            .contextMenu {
                                Button("Remove Source", role: .destructive) {
                                    let transcriptIds = Set(detail.transcripts.map(\.id))
                                    Task {
                                        await viewModel.removeSource(
                                            sourceId: detail.source.id,
                                            documentId: documentId
                                        )
                                        if let selected = selectedTranscriptId, transcriptIds.contains(selected) {
                                            selectedTranscriptId = nil
                                        }
                                    }
                                }
                            }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            Divider()

            navigatorBottomBar
        }
    }

    private var navigatorHeaderBar: some View {
        HStack {
            Text("Sources")
                .font(.headline)

            Spacer()

            Button {
                showRecordingPicker = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Add Source")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var navigatorBottomBar: some View {
        HStack {
            Spacer()

            Button {
                addTranscriptSourceId = selectedSourceId
            } label: {
                Label("Add Variant", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(selectedSourceId == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Content Inspector (Right Pane)

    private var contentInspector: some View {
        VStack(spacing: 0) {
            audioPlayerPlaceholder

            Divider()

            if selectedTranscript != nil {
                transcriptContentView
            } else {
                emptyStateNoSelection
            }
        }
        .frame(minWidth: 300)
    }

    private var audioPlayerPlaceholder: some View {
        HStack(spacing: 12) {
            Button {} label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .disabled(true)

            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(height: 32)

            Text(selectedRecording?.durationSeconds?.formattedDuration ?? "--:--")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 72)
        .background(.regularMaterial)
    }

    private var emptyStateNoSelection: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("Select a transcript to preview")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var transcriptContentView: some View {
        if let transcript = selectedTranscript {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        transcriptBody(transcript)
                    } header: {
                        transcriptHeader(transcript)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                transcriptActionBar(transcript)
            }
        }
    }

    private func transcriptHeader(_ transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transcript.title ?? "Variant \(transcript.id)")
                    .font(.headline)

                if transcript.isPrimary {
                    Text("Primary")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundColor(.accentColor)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Text(transcript.modifiedAt, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let fullText = transcript.fullText {
                    let wordCount = fullText.split(separator: " ").count
                    Text("\u{2022}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(wordCount) words")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func transcriptBody(_ transcript: Transcript) -> some View {
        if let fullText = transcript.fullText, !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MarkdownEditableView(
                text: .constant(fullText),
                isEditing: .constant(false),
                placeholder: "No transcript"
            )
        } else {
            VStack(spacing: 8) {
                Text("No transcript text")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func transcriptActionBar(_ transcript: Transcript) -> some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                if transcript.isPrimary {
                    Label("Currently used as Document Body", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                } else {
                    Spacer()

                    Button {
                        showPromoteConfirmation = true
                    } label: {
                        Label("Use as Document Body", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    // MARK: - Actions

    private func promoteTranscript(_ transcript: Transcript) {
        let sourceId = transcript.sourceId

        Task {
            await viewModel.setPrimary(
                transcriptId: transcript.id,
                sourceId: sourceId,
                documentId: documentId
            )
            onBodyUpdated?()
        }
    }
}

// MARK: - Private Subviews

private struct SourceSectionHeader: View {
    let detail: SourceWithDetails

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.recording?.displayTitle ?? detail.source.displayName ?? "Source")
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    if let recording = detail.recording {
                        Text(recording.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let duration = recording.durationSeconds {
                            Text("\u{2022}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(duration.formattedDuration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text("\(detail.transcripts.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct TranscriptNavigatorRow: View {
    let transcript: Transcript

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: transcript.isPrimary ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundStyle(transcript.isPrimary ? Color.orange : Color(white: 0.5, opacity: 0.5))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.title ?? "Variant \(transcript.id)")
                    .font(.body)
                    .lineLimit(1)

                if let fullText = transcript.fullText {
                    Text(fullText.prefix(100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(transcript.modifiedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if transcript.isPrimary {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
            }
        }
    }
}

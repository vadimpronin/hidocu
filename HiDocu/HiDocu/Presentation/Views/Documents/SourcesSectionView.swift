//
//  SourcesSectionView.swift
//  HiDocu
//
//  Sources list for a document's Sources tab.
//

import SwiftUI

struct SourcesSectionView: View {
    var viewModel: SourcesViewModel
    let documentId: Int64
    @State private var showingRecordingPicker = false
    @State private var editingSource: SourceWithDetails?

    var body: some View {
        List {
            ForEach(viewModel.sources) { detail in
                DisclosureGroup {
                    ForEach(detail.transcripts) { transcript in
                        TranscriptRow(
                            transcript: transcript,
                            sourceId: detail.source.id,
                            documentId: documentId,
                            viewModel: viewModel
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: "waveform")
                        VStack(alignment: .leading) {
                            Text(detail.recording?.displayTitle ?? detail.source.displayName ?? "Source")
                                .font(.body)
                            if let rec = detail.recording {
                                Text(rec.formattedFileSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .contextMenu {
                    Button("Edit Transcripts") {
                        editingSource = detail
                    }
                    Button("Remove Source", role: .destructive) {
                        Task {
                            await viewModel.removeSource(sourceId: detail.source.id, documentId: documentId)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingRecordingPicker = true
                } label: {
                    Label("Add Source", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingRecordingPicker) {
            RecordingPickerView(
                documentId: documentId,
                viewModel: viewModel,
                recordingRepository: viewModel.recordingRepository
            )
        }
        .sheet(item: $editingSource) { source in
            TranscriptEditorView(
                sourceId: source.source.id,
                documentId: documentId,
                viewModel: viewModel,
                transcripts: source.transcripts
            )
            .frame(minWidth: 500, minHeight: 400)
        }
        .task {
            await viewModel.loadSources(documentId: documentId)
        }
    }
}

// MARK: - Transcript Row

private struct TranscriptRow: View {
    let transcript: Transcript
    let sourceId: Int64
    let documentId: Int64
    var viewModel: SourcesViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(transcript.title ?? "Variant \(transcript.id)")
                        .font(.body)
                    if transcript.isPrimary {
                        Text("Primary")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                if let text = transcript.fullText {
                    Text(text.prefix(100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .contextMenu {
            if !transcript.isPrimary {
                Button("Set as Primary") {
                    Task {
                        await viewModel.setPrimary(
                            transcriptId: transcript.id,
                            sourceId: sourceId,
                            documentId: documentId
                        )
                    }
                }
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteTranscript(id: transcript.id, documentId: documentId)
                }
            }
        }
    }
}

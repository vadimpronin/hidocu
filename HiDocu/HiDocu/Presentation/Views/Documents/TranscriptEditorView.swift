//
//  TranscriptEditorView.swift
//  HiDocu
//
//  Per-source transcript management with variant tabs.
//

import SwiftUI

struct TranscriptEditorView: View {
    let sourceId: Int64
    let documentId: Int64
    var viewModel: SourcesViewModel
    let transcripts: [Transcript]

    @State private var selectedTranscriptId: Int64?
    @State private var editedText = ""
    @State private var showAddSheet = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isTranscriptEditing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Variant tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(transcripts) { transcript in
                        Button {
                            selectTranscript(transcript)
                        } label: {
                            HStack(spacing: 4) {
                                Text(transcript.title ?? "Variant \(transcript.id)")
                                    .font(.caption)
                                if transcript.isPrimary {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTranscriptId == transcript.id ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // Editor toolbar
            HStack {
                Spacer()
                Button(isTranscriptEditing ? "Done" : "Edit") {
                    isTranscriptEditing.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Editor
            MarkdownEditableView(
                text: $editedText,
                isEditing: $isTranscriptEditing,
                placeholder: "No transcript"
            )
            .onChange(of: editedText) { _, _ in
                guard let transcriptId = selectedTranscriptId else { return }
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await viewModel.updateTranscriptText(
                        id: transcriptId,
                        text: editedText,
                        documentId: documentId
                    )
                }
            }
        }
        .onAppear {
            if let first = transcripts.first {
                selectTranscript(first)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTranscriptSheet(sourceId: sourceId, documentId: documentId, viewModel: viewModel)
        }
    }

    private func selectTranscript(_ transcript: Transcript) {
        selectedTranscriptId = transcript.id
        editedText = transcript.fullText ?? ""
        isTranscriptEditing = false
    }
}

// MARK: - Add Transcript Sheet

private struct AddTranscriptSheet: View {
    let sourceId: Int64
    let documentId: Int64
    var viewModel: SourcesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Transcript Variant")
                .font(.headline)

            TextField("Title (optional)", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(height: 200)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    Task {
                        await viewModel.addTranscript(
                            sourceId: sourceId,
                            text: text,
                            title: title.isEmpty ? nil : title,
                            documentId: documentId
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }
}

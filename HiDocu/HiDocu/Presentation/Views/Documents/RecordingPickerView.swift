//
//  RecordingPickerView.swift
//  HiDocu
//
//  Sheet for selecting a recording to attach as a source.
//

import SwiftUI

struct RecordingPickerView: View {
    let documentId: Int64
    var viewModel: SourcesViewModel
    let recordingRepository: any RecordingRepositoryV2
    @Environment(\.dismiss) private var dismiss

    @State private var recordings: [RecordingV2] = []
    @State private var filterText = ""
    @State private var isLoading = true

    var filteredRecordings: [RecordingV2] {
        if filterText.isEmpty {
            return recordings
        }
        return recordings.filter {
            $0.filename.localizedCaseInsensitiveContains(filterText) ||
            ($0.title?.localizedCaseInsensitiveContains(filterText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Recording")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            TextField("Filter...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredRecordings) { recording in
                    let isAttached = viewModel.sources.contains {
                        $0.source.recordingId == recording.id
                    }

                    Button {
                        Task {
                            await viewModel.addSource(
                                documentId: documentId,
                                recordingId: recording.id,
                                displayName: recording.displayTitle
                            )
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(recording.displayTitle)
                                    .foregroundStyle(isAttached ? .secondary : .primary)
                                Text(recording.formattedFileSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isAttached {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isAttached)
                }
            }
        }
        .frame(width: 400, height: 500)
        .task {
            do {
                recordings = try await recordingRepository.fetchAll()
            } catch {
                AppLogger.general.error("Failed to load recordings: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

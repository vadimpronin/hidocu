//
//  RecordingsListView.swift
//  HiDocu
//
//  Displays recordings grouped by date with filtering support.
//

import SwiftUI

struct RecordingsListView: View {
    var viewModel: RecordingsListViewModel
    @Binding var selectedRecordingId: Int64?

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.groups.isEmpty {
                emptyView
            } else {
                populatedView
            }
        }
        .task {
            viewModel.startObserving()
        }
        .onDisappear {
            viewModel.stopObserving()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading recordings...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Recordings Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect your HiDock device and sync, or drag audio files here to import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Populated

    private var populatedView: some View {
        List(selection: $selectedRecordingId) {
            ForEach(viewModel.groups) { group in
                Section {
                    ForEach(group.recordings) { recording in
                        RecordingRowView(recording: recording)
                            .tag(recording.id)
                            .contextMenu {
                                Button("Copy Title") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        recording.displayTitle,
                                        forType: .string
                                    )
                                }

                                Button("Show in Finder") {
                                    let url = URL(fileURLWithPath: recording.filepath)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .disabled(recording.status == .new)

                                Divider()

                                Button("Delete", role: .destructive) {
                                    // Placeholder for future delete implementation
                                }
                            }
                    }
                } header: {
                    Text(group.headerTitle)
                }
            }
        }
    }
}

//
//  AllRecordingsView.swift
//  HiDocu
//
//  Simple flat table of ALL recordings across all sources.
//  Shown when "All Recordings" is selected in the sidebar.
//

import SwiftUI

struct AllRecordingsView: View {
    let recordingRepository: any RecordingRepositoryV2
    let recordingSourceRepository: any RecordingSourceRepository

    @State private var recordings: [RecordingV2] = []
    @State private var sources: [Int64: RecordingSource] = [:]  // sourceId -> source for display
    @State private var selection: Set<Int64> = []
    @State private var sortOrder: [KeyPathComparator<RecordingV2>] = [
        .init(\.createdAt, order: .reverse)
    ]
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var sortedRecordings: [RecordingV2] {
        recordings.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if isLoading && recordings.isEmpty {
                ProgressView("Loading recordings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if recordings.isEmpty {
                emptyState
            } else {
                recordingTable
            }
        }
        .navigationTitle("All Recordings")
        .task {
            await loadData()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadData() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh recordings")
                .disabled(isLoading)
            }
        }
    }

    // MARK: - Recording Table

    private var recordingTable: some View {
        Table(sortedRecordings, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Source") { recording in
                if let sourceId = recording.recordingSourceId,
                   let source = sources[sourceId] {
                    Text(source.name)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unknown")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 120, ideal: 150)

            TableColumn("Name", value: \.filename) { recording in
                Text(recording.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
            }
            .width(min: 150, ideal: 270)

            TableColumn("Date", value: \.createdAt) { recording in
                Text(recording.createdAt.formatted(
                    .dateTime
                        .day(.twoDigits)
                        .month(.abbreviated)
                        .year()
                        .hour(.twoDigits(amPM: .omitted))
                        .minute(.twoDigits)
                        .second(.twoDigits)
                ))
                .monospacedDigit()
            }
            .width(min: 180, ideal: 190)

            TableColumn("Duration") { recording in
                if let duration = recording.durationSeconds {
                    Text(duration.formattedDurationFull)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 80)

            TableColumn("Mode") { recording in
                Text(recording.recordingMode?.displayName ?? "—")
            }
            .width(min: 55, ideal: 70)

            TableColumn("Size") { recording in
                if let size = recording.fileSizeBytes {
                    Text(size.formattedFileSize)
                        .monospacedDigit()
                } else {
                    Text("--")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 60, ideal: 80)

            TableColumn("Status", sortUsing: KeyPathComparator(\.syncStatus)) { recording in
                StatusBadge(status: recording.syncStatus)
            }
            .width(min: 70, ideal: 90)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No Recordings")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Import recordings from a connected device to get started.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await loadData() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Load recordings and sources in parallel
            async let recordingsTask = recordingRepository.fetchAll()
            async let sourcesTask = recordingSourceRepository.fetchAll()

            let (loadedRecordings, loadedSources) = try await (recordingsTask, sourcesTask)

            recordings = loadedRecordings
            sources = Dictionary(
                loadedSources.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.recordings.error("Failed to load all recordings: \(error.localizedDescription)")
        }

        isLoading = false
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: RecordingSyncStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusLabel)
                .font(.caption2)
        }
    }

    private var statusColor: Color {
        switch status {
        case .onDeviceOnly:
            return .orange
        case .synced:
            return .green
        case .localOnly:
            return .blue
        }
    }

    private var statusLabel: String {
        switch status {
        case .onDeviceOnly:
            return "On Device"
        case .synced:
            return "Synced"
        case .localOnly:
            return "Local Only"
        }
    }
}

//
//  RecordingDetailView.swift
//  HiDocu
//
//  Detail view for a single recording with playback controls and waveform.
//

import SwiftUI

/// Detail view for viewing and playing a recording.
///
/// Features:
/// - Inline title editing
/// - Audio playback with waveform visualization
/// - Playback rate control
/// - Metadata display
struct RecordingDetailView: View {

    // MARK: - Properties

    @State private var viewModel: RecordingDetailViewModel
    @State private var transcriptionViewModel: TranscriptionViewModel

    // MARK: - Initialization

    init(recording: Recording, container: AppDependencyContainer) {
        let vm = RecordingDetailViewModel(
            recording: recording,
            playerService: container.audioPlayerService,
            waveformAnalyzer: container.waveformAnalyzer,
            fileSystemService: container.fileSystemService,
            repository: container.recordingRepository
        )
        _viewModel = State(initialValue: vm)

        let tvm = TranscriptionViewModel(
            recordingId: recording.id,
            recordingTitle: recording.displayTitle,
            repository: container.transcriptionRepository
        )
        _transcriptionViewModel = State(initialValue: tvm)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Section
                headerSection

                // Player Section
                playerSection
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                // Transcription Section
                TranscriptionSectionView(viewModel: transcriptionViewModel)

                // Metadata Section
                metadataSection

                Spacer()
            }
            .padding()
        }
        .navigationTitle(viewModel.editableTitle)
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            Task {
                await transcriptionViewModel.saveCurrentText()
                await viewModel.onDisappear()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Editable title
            TextField("Title", text: $viewModel.editableTitle)
                .textFieldStyle(.plain)
                .font(.title)
                .onChange(of: viewModel.editableTitle) { _, _ in
                    viewModel.markTitleModified()
                }
                .onSubmit {
                    Task {
                        await viewModel.saveTitle()
                    }
                }

            // Date and duration
            HStack {
                if let createdAt = viewModel.getRecording().createdAt {
                    Text(createdAt, format: .dateTime.month().day().year().hour().minute())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(viewModel.getRecording().formattedDuration)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    // MARK: - Player Section

    private var playerSection: some View {
        VStack(spacing: 16) {
            // Loading or error state
            if viewModel.isLoading {
                ProgressView("Loading audio...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if let error = viewModel.playerError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)

                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        Task {
                            await viewModel.onAppear()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                // Waveform
                waveformSection

                // Time labels
                HStack {
                    Text(viewModel.currentTime.formattedTimestamp)
                    Spacer()
                    Text(viewModel.duration.formattedTimestamp)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

                // Play/Pause button
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help(viewModel.isPlaying ? "Pause" : "Play")

                // Playback rate selector
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.2f")x") {
                            viewModel.setRate(Float(rate))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge")
                        Text("\(viewModel.playbackRate, specifier: "%.2f")x")
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        Group {
            if viewModel.isAnalyzingWaveform {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Analyzing audio...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.waveformError {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
            } else if !viewModel.waveformSamples.isEmpty {
                WaveformView(
                    samples: viewModel.waveformSamples,
                    progress: viewModel.progress,
                    onSeek: { progress in
                        Task {
                            await viewModel.seek(to: progress)
                        }
                    }
                )
                .frame(height: 100)
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        GroupBox("Details") {
            VStack(alignment: .leading, spacing: 12) {
                let recording = viewModel.getRecording()

                MetadataRow(label: "File size", value: recording.formattedFileSize)
                MetadataRow(label: "Device", value: recording.deviceModel ?? "Unknown")

                if let mode = recording.recordingMode {
                    MetadataRow(label: "Mode", value: mode.rawValue.capitalized)
                }

                MetadataRow(label: "Status", value: recording.status.rawValue.capitalized)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(recording.filepath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Metadata Row Component

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#Preview {
    let container = AppDependencyContainer()
    NavigationStack {
        RecordingDetailView(
            recording: Recording(
                id: 1,
                filename: "CALL_20260203_140500.hda",
                filepath: "2026/02/CALL_20260203_140500.hda",
                title: "Team Sync Meeting",
                durationSeconds: 3665,
                fileSizeBytes: 52428800,
                createdAt: Date(),
                deviceModel: "HiDock P1",
                recordingMode: .call,
                status: .downloaded
            ),
            container: container
        )
    }
}

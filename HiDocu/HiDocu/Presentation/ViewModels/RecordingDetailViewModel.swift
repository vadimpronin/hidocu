//
//  RecordingDetailViewModel.swift
//  HiDocu
//
//  View model for the recording detail view.
//  Coordinates audio playback and waveform visualization.
//

import Foundation

/// View model for the recording detail screen.
///
/// Manages:
/// - Audio playback through AudioPlayerService
/// - Waveform generation through WaveformAnalyzer
/// - Recording metadata editing
/// - Lifecycle (load on appear, save on disappear)
@Observable @MainActor
final class RecordingDetailViewModel {

    // MARK: - Input (injected)

    private let recording: Recording
    private let playerService: AudioPlayerService
    private let waveformAnalyzer: WaveformAnalyzer
    private let fileSystemService: FileSystemService
    private let repository: RecordingRepository

    // MARK: - Output (published)

    private(set) var waveformSamples: [Float] = []
    private(set) var isAnalyzingWaveform: Bool = false
    private(set) var waveformError: String?

    /// Editable title (bound to TextField)
    var editableTitle: String

    /// Whether title has been modified
    private var titleModified: Bool = false

    // MARK: - Computed Properties (from AudioPlayerService)

    var isPlaying: Bool {
        playerService.isPlaying
    }

    var currentTime: TimeInterval {
        playerService.currentTime
    }

    var duration: TimeInterval {
        playerService.duration
    }

    var playbackRate: Float {
        playerService.playbackRate
    }

    var isLoading: Bool {
        playerService.isLoading
    }

    var playerError: String? {
        playerService.error
    }

    /// Playback progress (0.0-1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    // MARK: - Initialization

    init(
        recording: Recording,
        playerService: AudioPlayerService,
        waveformAnalyzer: WaveformAnalyzer,
        fileSystemService: FileSystemService,
        repository: RecordingRepository
    ) {
        self.recording = recording
        self.playerService = playerService
        self.waveformAnalyzer = waveformAnalyzer
        self.fileSystemService = fileSystemService
        self.repository = repository
        self.editableTitle = recording.title ?? recording.filename
    }

    // MARK: - Lifecycle

    /// Called when view appears
    func onAppear() async {
        // Load audio and generate waveform in parallel
        async let audioLoad: Void = loadAudio()
        async let waveformGen: Void = generateWaveform()

        _ = await (audioLoad, waveformGen)
    }

    /// Called when view disappears
    func onDisappear() async {
        // Save title if modified
        if titleModified {
            await saveTitle()
        }

        // Optionally pause playback
        if isPlaying {
            playerService.pause()
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        playerService.togglePlayPause()
    }

    func seek(to progress: Double) async {
        let time = progress * duration
        await playerService.seek(to: time)
    }

    func setRate(_ rate: Float) {
        playerService.setRate(rate)
    }

    // MARK: - Title Editing

    /// Mark title as modified (called by TextField onChange)
    func markTitleModified() {
        titleModified = true
    }

    /// Save edited title to database
    func saveTitle() async {
        guard titleModified else { return }

        do {
            var updatedRecording = recording
            updatedRecording.title = self.editableTitle.isEmpty ? nil : self.editableTitle

            try await repository.update(updatedRecording)

            titleModified = false

            AppLogger.ui.info("Title saved: \(self.editableTitle)")
        } catch {
            AppLogger.ui.error("Failed to save title: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// Load audio into player
    private func loadAudio() async {
        do {
            try await playerService.load(recording: recording)
        } catch {
            AppLogger.ui.error("Failed to load audio: \(error.localizedDescription)")
        }
    }

    /// Generate waveform visualization data
    private func generateWaveform() async {
        isAnalyzingWaveform = true
        waveformError = nil
        defer { isAnalyzingWaveform = false }

        do {
            let url = try fileSystemService.resolve(relativePath: recording.filepath)
            let samples = try await waveformAnalyzer.analyze(url: url, targetSampleCount: 200)
            self.waveformSamples = samples

            AppLogger.ui.info("Waveform generated: \(samples.count) samples")
        } catch {
            let message = "Failed to generate waveform: \(error.localizedDescription)"
            waveformError = message
            AppLogger.ui.error("\(message)")
        }
    }

    // MARK: - Accessors

    /// Get the original recording (for metadata display)
    func getRecording() -> Recording {
        recording
    }
}

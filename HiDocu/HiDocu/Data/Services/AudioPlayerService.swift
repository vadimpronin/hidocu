//
//  AudioPlayerService.swift
//  HiDocu
//
//  Audio playback service wrapping AVFoundation.
//  Handles .hda format, playback state, rate control, and position persistence.
//

import Foundation
import AVFoundation

/// Audio playback service managing the app's global audio player.
///
/// Features:
/// - Automatic .hda format handling via AudioCompatibilityService
/// - Playback rate control (0.5x - 2.0x)
/// - Position persistence (saves every 5 seconds)
/// - Observable state for SwiftUI binding
@Observable
final class AudioPlayerService {

    // MARK: - Published State (MainActor)

    @MainActor private(set) var isPlaying: Bool = false
    @MainActor private(set) var currentTime: TimeInterval = 0
    @MainActor private(set) var duration: TimeInterval = 0
    @MainActor private(set) var playbackRate: Float = 1.0
    @MainActor private(set) var error: String?
    @MainActor private(set) var currentRecording: Recording?
    @MainActor private(set) var isLoading: Bool = false

    // MARK: - Dependencies

    private let audioService: AudioCompatibilityService
    private let fileSystemService: FileSystemService
    private let repository: RecordingRepository

    // MARK: - AVFoundation (private)

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var positionSaveTimer: Timer?
    private var lastSavedPosition: TimeInterval = 0

    // MARK: - Constants

    private let timeObserverInterval: TimeInterval = 0.1  // Update every 100ms
    private let positionSaveInterval: TimeInterval = 5.0  // Save every 5 seconds

    // MARK: - Initialization

    init(
        audioService: AudioCompatibilityService,
        fileSystemService: FileSystemService,
        repository: RecordingRepository
    ) {
        self.audioService = audioService
        self.fileSystemService = fileSystemService
        self.repository = repository

        // Note: Audio session management not needed on macOS
        // AVPlayer handles audio routing automatically

        AppLogger.general.info("AudioPlayerService initialized")
    }

    deinit {
        // Critical: Remove time observer to prevent memory leaks
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        positionSaveTimer?.invalidate()

        AppLogger.general.info("AudioPlayerService deinitialized")
    }

    // MARK: - Public API

    /// Load a recording for playback.
    /// Automatically prepares .hda files for playback.
    @MainActor
    func load(recording: Recording) async throws {
        AppLogger.general.info("Loading recording: \(recording.displayTitle)")

        isLoading = true
        error = nil
        defer { isLoading = false }

        // Stop current playback
        stop()

        do {
            // Resolve file path
            let fileURL = try fileSystemService.resolve(relativePath: recording.filepath)

            // Prepare for playback (handles .hda format)
            let playableURL = try await audioService.prepareForPlayback(url: fileURL)

            // Create player item
            let playerItem = AVPlayerItem(url: playableURL)

            // Create or reuse player
            if let existingPlayer = player {
                existingPlayer.replaceCurrentItem(with: playerItem)
            } else {
                player = AVPlayer(playerItem: playerItem)
                setupTimeObserver()
            }

            // Wait for player to be ready
            try await waitForPlayerReady(playerItem)

            // Set duration
            if let loadedDuration = player?.currentItem?.duration.seconds,
               loadedDuration.isFinite {
                self.duration = loadedDuration
            }

            // Restore playback position
            if recording.playbackPositionSeconds > 0 {
                let position = TimeInterval(recording.playbackPositionSeconds)
                await seek(to: position)
            }

            // Update state
            self.currentRecording = recording
            self.lastSavedPosition = TimeInterval(recording.playbackPositionSeconds)

            AppLogger.general.info("Recording loaded successfully. Duration: \(self.duration)s")

        } catch {
            let message = "Failed to load recording: \(error.localizedDescription)"
            self.error = message
            AppLogger.general.error("\(message)")
            throw error
        }
    }

    /// Start playback
    @MainActor
    func play() {
        guard let player = player, player.currentItem != nil else {
            AppLogger.general.warning("Cannot play: no item loaded")
            return
        }

        player.play()
        isPlaying = true
        startPositionSaveTimer()

        AppLogger.general.debug("Playback started")
    }

    /// Pause playback
    @MainActor
    func pause() {
        player?.pause()
        isPlaying = false
        stopPositionSaveTimer()

        // Immediately save position on pause
        Task {
            await saveCurrentPosition()
        }

        AppLogger.general.debug("Playback paused")
    }

    /// Toggle play/pause
    @MainActor
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Seek to a specific time
    @MainActor
    func seek(to time: TimeInterval) async {
        guard let player = player else { return }

        let clampedTime = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        await withCheckedContinuation { continuation in
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }

        currentTime = clampedTime

        AppLogger.general.debug("Seeked to \(clampedTime)s")
    }

    /// Set playback rate
    @MainActor
    func setRate(_ rate: Float) {
        let clampedRate = max(0.5, min(2.0, rate))
        player?.rate = clampedRate
        playbackRate = clampedRate

        // If we were playing, ensure we continue playing at new rate
        if isPlaying {
            player?.play()
        }

        AppLogger.general.debug("Playback rate set to \(clampedRate)x")
    }

    /// Stop playback and reset
    @MainActor
    func stop() {
        player?.pause()
        isPlaying = false
        stopPositionSaveTimer()

        // Save position before stopping
        Task {
            await saveCurrentPosition()
        }

        player?.seek(to: .zero)
        currentTime = 0

        AppLogger.general.debug("Playback stopped")
    }

    // MARK: - Private Methods

    /// Setup periodic time observer
    private func setupTimeObserver() {
        let interval = CMTime(seconds: timeObserverInterval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }

    /// Wait for player item to be ready
    private func waitForPlayerReady(_ item: AVPlayerItem) async throws {
        // Wait for status to change from .unknown
        for _ in 0..<50 {  // Max 5 seconds (50 * 100ms)
            if item.status == .readyToPlay {
                return
            } else if item.status == .failed {
                throw AudioPlayerError.playerItemFailed(item.error?.localizedDescription ?? "Unknown error")
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw AudioPlayerError.loadTimeout
    }

    /// Start timer to periodically save playback position
    @MainActor
    private func startPositionSaveTimer() {
        stopPositionSaveTimer()

        positionSaveTimer = Timer.scheduledTimer(
            withTimeInterval: positionSaveInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.saveCurrentPosition()
            }
        }
    }

    /// Stop position save timer
    @MainActor
    private func stopPositionSaveTimer() {
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
    }

    /// Save current playback position to database
    @MainActor
    private func saveCurrentPosition() async {
        guard let recording = currentRecording else { return }

        let position = Int(currentTime)

        // Only save if position changed significantly (1 second threshold)
        guard abs(currentTime - lastSavedPosition) >= 1.0 else { return }

        do {
            try await repository.updatePlaybackPosition(id: recording.id, seconds: position)
            lastSavedPosition = currentTime

            AppLogger.general.debug("Saved playback position: \(position)s")
        } catch {
            AppLogger.general.error("Failed to save playback position: \(error.localizedDescription)")
        }
    }

}

// MARK: - Errors

enum AudioPlayerError: LocalizedError {
    case playerItemFailed(String)
    case loadTimeout
    case noPlayerItem

    var errorDescription: String? {
        switch self {
        case .playerItemFailed(let reason):
            return "Player item failed: \(reason)"
        case .loadTimeout:
            return "Loading timed out"
        case .noPlayerItem:
            return "No audio loaded"
        }
    }
}

//
//  WaveformAnalyzer.swift
//  HiDocu
//
//  Extracts audio waveform data for visualization.
//  Uses AVAssetReader to read PCM samples and calculate RMS amplitudes.
//

import Foundation
import AVFoundation
import Accelerate

/// Service for generating waveform visualization data from audio files.
/// Extracts RMS (Root Mean Square) amplitudes and normalizes them for display.
final class WaveformAnalyzer: @unchecked Sendable {

    // MARK: - Dependencies

    private let fileSystemService: FileSystemService

    // MARK: - Initialization

    init(fileSystemService: FileSystemService) {
        self.fileSystemService = fileSystemService
    }

    // MARK: - Public API

    /// Generate waveform data from an audio file.
    ///
    /// - Parameters:
    ///   - url: URL of the audio file
    ///   - targetSampleCount: Number of samples to generate (default: 200 bars)
    /// - Returns: Array of normalized amplitudes (0.0-1.0)
    /// - Throws: WaveformError on failure
    func analyze(url: URL, targetSampleCount: Int = 200) async throws -> [Float] {
        AppLogger.fileSystem.info("Starting waveform analysis for \(url.lastPathComponent)")

        return try await self.fileSystemService.withSecurityScopedAccess(to: url) {
            try await self.extractWaveformData(from: url, targetSampleCount: targetSampleCount)
        }
    }

    // MARK: - Private Implementation

    /// Extract waveform data using AVAssetReader
    private func extractWaveformData(from url: URL, targetSampleCount: Int) async throws -> [Float] {
        let asset = AVURLAsset(url: url)

        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }

        // Create asset reader
        let reader = try AVAssetReader(asset: asset)

        // Configure output settings (Linear PCM)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        // Start reading
        guard reader.startReading() else {
            throw WaveformError.cannotStartReading(reader.error?.localizedDescription ?? "Unknown error")
        }

        // Read all samples and calculate RMS
        var sampleBuffers: [[Float]] = []

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if let samples = try? self.extractSamplesFromBuffer(sampleBuffer) {
                sampleBuffers.append(samples)
            }
        }

        // Flatten all buffers into single array
        let allSamples = sampleBuffers.flatMap { $0 }

        guard !allSamples.isEmpty else {
            throw WaveformError.noSamplesRead
        }

        AppLogger.fileSystem.debug("Extracted \(allSamples.count) total samples")

        // Downsample to target count
        let downsampled = downsample(samples: allSamples, targetCount: targetSampleCount)

        // Normalize to 0.0-1.0 range
        let normalized = normalize(samples: downsampled)

        AppLogger.fileSystem.info("Waveform analysis complete: \(normalized.count) samples")

        return normalized
    }

    /// Extract Float samples from CMSampleBuffer
    private func extractSamplesFromBuffer(_ sampleBuffer: CMSampleBuffer) throws -> [Float] {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return []
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let data = dataPointer else {
            return []
        }

        // Convert Int16 PCM samples to Float
        let sampleCount = length / MemoryLayout<Int16>.size
        let samples = UnsafeBufferPointer(start: data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }, count: sampleCount)

        return samples.map { Float($0) / Float(Int16.max) }
    }

    /// Downsample samples to target count using RMS
    private func downsample(samples: [Float], targetCount: Int) -> [Float] {
        guard samples.count > targetCount else {
            return samples
        }

        let chunkSize = samples.count / targetCount
        var downsampled: [Float] = []

        for i in 0..<targetCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            let chunk = Array(samples[start..<end])

            // Calculate RMS for this chunk
            let rms = calculateRMS(samples: chunk)
            downsampled.append(rms)
        }

        return downsampled
    }

    /// Calculate Root Mean Square of samples
    private func calculateRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        var sumOfSquares: Float = 0.0
        vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(samples.count))

        return sqrt(sumOfSquares / Float(samples.count))
    }

    /// Normalize samples to 0.0-1.0 range
    private func normalize(samples: [Float]) -> [Float] {
        guard let maxValue = samples.max(), maxValue > 0 else {
            return samples.map { _ in 0.0 }
        }

        return samples.map { $0 / maxValue }
    }
}

// MARK: - Errors

enum WaveformError: LocalizedError {
    case noAudioTrack
    case cannotStartReading(String)
    case noSamplesRead
    case fileAccessError(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in file"
        case .cannotStartReading(let reason):
            return "Cannot start reading audio: \(reason)"
        case .noSamplesRead:
            return "No audio samples could be read from file"
        case .fileAccessError(let reason):
            return "File access error: \(reason)"
        }
    }
}

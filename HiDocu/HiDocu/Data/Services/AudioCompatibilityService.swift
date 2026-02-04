//
//  AudioCompatibilityService.swift
//  HiDocu
//
//  Handles audio file validation and compatibility for playback.
//  The HiDock device uses a proprietary .hda extension (which is essentially MP3).
//

import Foundation
import AVFoundation

/// Service for validating audio files and preparing them for playback.
/// Handles the proprietary .hda format by creating playback-compatible hard links.
final class AudioCompatibilityService: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Directory for temporary playback files (hard links with .mp3 extension)
    private let cacheDirectory: URL
    
    /// Standard audio extensions that don't need conversion
    private let standardExtensions = ["mp3", "m4a", "wav", "aac", "aiff"]
    
    // MARK: - Initialization
    
    init() {
        // Create a subdirectory in temp for our hard links
        let tempDir = FileManager.default.temporaryDirectory
        self.cacheDirectory = tempDir.appendingPathComponent("HiDocu-AudioCache", isDirectory: true)
        
        // Ensure cache directory exists
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        AppLogger.fileSystem.info("AudioCompatibilityService initialized. Cache: \(self.cacheDirectory.path)")
    }
    
    // MARK: - Validation
    
    /// Validate a downloaded audio file.
    ///
    /// Performs two checks:
    /// 1. File size matches expected value
    /// 2. AVFoundation can read the file and reports duration > 0
    ///
    /// - Parameters:
    ///   - url: URL of the downloaded file
    ///   - expectedSize: Expected file size in bytes
    /// - Throws: AudioValidationError on validation failure
    func validate(url: URL, expectedSize: Int) async throws {
        AppLogger.fileSystem.info("Validating \(url.lastPathComponent) (expected \(expectedSize) bytes)")

        // Check 1: File size — hard requirement
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualSize = attributes[.size] as? Int ?? 0

        if actualSize != expectedSize {
            AppLogger.fileSystem.error("Size mismatch for \(url.lastPathComponent): expected \(expectedSize), got \(actualSize)")
            throw AudioValidationError.fileSizeMismatch(expected: expectedSize, actual: actualSize)
        }

        // Check 2: Audio integrity via AVURLAsset — best effort.
        // Non-standard extensions (e.g. .hda) may not be readable by AVFoundation
        // even though they contain valid audio data. Log a warning but don't fail.
        let ext = url.pathExtension.lowercased()
        let validationURL: URL
        if standardExtensions.contains(ext) {
            validationURL = url
        } else {
            do {
                validationURL = try await createPlaybackLink(for: url)
            } catch {
                AppLogger.fileSystem.warning("Could not create validation link for .\(ext) file — skipping audio check")
                return
            }
        }

        do {
            let asset = AVURLAsset(url: validationURL)
            let cmDuration = try await asset.load(.duration)
            let duration = cmDuration.seconds

            if duration.isNaN || duration <= 0 {
                AppLogger.fileSystem.warning("AVFoundation reports invalid duration for \(url.lastPathComponent): \(duration) — file may still be playable")
            } else {
                AppLogger.fileSystem.info("Validated \(url.lastPathComponent): \(actualSize) bytes, \(String(format: "%.1f", duration))s")
            }
        } catch {
            AppLogger.fileSystem.warning("AVFoundation could not read \(url.lastPathComponent): \(error.localizedDescription) — file size is correct, continuing")
        }
    }

    /// Validate a downloaded audio file asynchronously.
    func validateAsync(url: URL, expectedSize: Int) async throws {
        try await validate(url: url, expectedSize: expectedSize)
    }
    
    // MARK: - Duration Extraction
    
    /// Get the duration of an audio file in seconds.
    ///
    /// - Parameter url: URL of the audio file
    /// - Returns: Duration in seconds (rounded)
    /// - Throws: AudioValidationError if duration cannot be read
    func getDuration(url: URL) async throws -> Int {
        // For non-standard extensions (e.g. .hda), use a playback-compatible link
        let ext = url.pathExtension.lowercased()
        let assetURL: URL
        if standardExtensions.contains(ext) {
            assetURL = url
        } else {
            assetURL = try await createPlaybackLink(for: url)
        }

        let asset = AVURLAsset(url: assetURL)
        let cmDuration = try await asset.load(.duration)
        let duration = cmDuration.seconds

        if duration.isNaN || duration <= 0 {
            throw AudioValidationError.cannotReadDuration
        }

        return Int(duration.rounded())
    }
    
    // MARK: - Playback Preparation (The Hard Link Trick)
    
    /// Prepare a file for playback by ensuring it has a compatible extension.
    ///
    /// System audio players often reject the `.hda` extension despite it being
    /// valid MP3 data. This method creates a hard link (or copy as fallback)
    /// with an `.mp3` extension for playback.
    ///
    /// - Parameter url: Original file URL
    /// - Returns: URL suitable for playback (may be original or hard link)
    func prepareForPlayback(url: URL) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        
        // Standard extensions are playable as-is
        if standardExtensions.contains(ext) {
            return url
        }
        
        // For .hda files, create a hard link with .mp3 extension
        return try await createPlaybackLink(for: url)
    }
    
    /// Create a hard link with .mp3 extension for playback.
    ///
    /// Hard links are efficient: they share the same inode/data blocks.
    /// Falls back to copy if hard link fails (e.g., cross-volume).
    private func createPlaybackLink(for url: URL) async throws -> URL {
        try await Task.detached {
            let filename = url.deletingPathExtension().lastPathComponent
            let linkedURL = self.cacheDirectory.appendingPathComponent("\(filename).mp3")
            
            // Check if link already exists
            if FileManager.default.fileExists(atPath: linkedURL.path) {
                // Verify it's still valid (original file exists and sizes match)
                if let originalAttrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let linkedAttrs = try? FileManager.default.attributesOfItem(atPath: linkedURL.path),
                   let originalSize = originalAttrs[.size] as? Int,
                   let linkedSize = linkedAttrs[.size] as? Int,
                   originalSize == linkedSize {
                    return linkedURL
                }
                // Invalid link, remove it
                try? FileManager.default.removeItem(at: linkedURL)
            }
            
            // Try hard link first (most efficient)
            do {
                try FileManager.default.linkItem(at: url, to: linkedURL)
                AppLogger.fileSystem.debug("Created hard link: \(linkedURL.lastPathComponent)")
                return linkedURL
            } catch {
                // Hard link failed (possibly cross-volume), fall back to copy
                AppLogger.fileSystem.warning("Hard link failed, using copy: \(error.localizedDescription)")
                try FileManager.default.copyItem(at: url, to: linkedURL)
                AppLogger.fileSystem.debug("Created copy: \(linkedURL.lastPathComponent)")
                return linkedURL
            }
        }.value
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached playback files.
    /// Should be called periodically or on app termination.
    func clearCache() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
            
            for fileURL in contents {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            AppLogger.fileSystem.info("Cleared audio cache: \(contents.count) files")
        } catch {
            AppLogger.fileSystem.error("Failed to clear audio cache: \(error.localizedDescription)")
        }
    }
    
    /// Get the current size of the cache directory.
    func getCacheSize() -> Int {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            
            return contents.reduce(0) { total, url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return total + size
            }
        } catch {
            return 0
        }
    }
}

// MARK: - Errors

enum AudioValidationError: LocalizedError {
    case fileSizeMismatch(expected: Int, actual: Int)
    case invalidAudioFile(String)
    case cannotReadDuration
    case playbackPreparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileSizeMismatch(let expected, let actual):
            let expectedStr = ByteCountFormatter.string(fromByteCount: Int64(expected), countStyle: .file)
            let actualStr = ByteCountFormatter.string(fromByteCount: Int64(actual), countStyle: .file)
            return "The file size does not match: expected \(expectedStr) but got \(actualStr). The file may be corrupted."
        case .invalidAudioFile:
            return "The file does not appear to be a valid audio recording."
        case .cannotReadDuration:
            return "Could not determine the audio duration. The file format may not be supported."
        case .playbackPreparationFailed:
            return "Could not prepare the file for playback. Try re-importing the recording."
        }
    }
}

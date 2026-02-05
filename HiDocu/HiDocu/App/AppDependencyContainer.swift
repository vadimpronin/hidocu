//
//  AppDependencyContainer.swift
//  HiDocu
//
//  Centralized dependency injection container.
//  Uses pure initializer injection - no 3rd party DI frameworks.
//

import Foundation
import SwiftUI

/// Centralized container for all app dependencies.
/// All services are initialized here and injected where needed.
///
/// - Important: `DeviceConnectionService` is a singleton that must remain alive
///   for the app's lifetime to maintain USB connection.
@Observable
final class AppDependencyContainer {
    
    // MARK: - Services (Long-lived Singletons)
    
    /// Database manager - handles SQLite operations
    let databaseManager: DatabaseManager
    
    /// File system service - handles sandbox-compliant file operations
    let fileSystemService: FileSystemService
    
    /// Device manager - manages multiple device connections (MUST stay alive)
    let deviceManager: DeviceManager
    
    /// Audio compatibility service - handles .hda format and validation
    let audioService: AudioCompatibilityService

    /// Waveform analyzer - extracts visualization data from audio files
    let waveformAnalyzer: WaveformAnalyzer

    /// Audio player service - manages playback (MUST stay alive)
    let audioPlayerService: AudioPlayerService

    // MARK: - Repositories

    /// Recording repository for data access
    let recordingRepository: SQLiteRecordingRepository

    /// Transcription repository for data access
    let transcriptionRepository: SQLiteTranscriptionRepository

    // MARK: - Import Services

    /// Recording import service - handles device-to-local import
    let importService: RecordingImportService
    
    // MARK: - Initialization
    
    init() {
        AppLogger.general.info("Initializing AppDependencyContainer...")
        
        // Initialize database
        do {
            self.databaseManager = try DatabaseManager()
        } catch {
            // Fatal error - app cannot function without database
            fatalError("Failed to initialize database: \(error.localizedDescription)")
        }
        
        // Initialize file system service
        self.fileSystemService = FileSystemService()
        
        // Initialize device manager (long-lived singleton)
        self.deviceManager = DeviceManager()
        
        // Initialize audio compatibility service
        self.audioService = AudioCompatibilityService()

        // Initialize waveform analyzer
        self.waveformAnalyzer = WaveformAnalyzer(fileSystemService: fileSystemService)

        // Initialize repositories (with FileSystemService for path mapping)
        self.recordingRepository = SQLiteRecordingRepository(
            databaseManager: databaseManager,
            fileSystemService: fileSystemService
        )

        self.transcriptionRepository = SQLiteTranscriptionRepository(
            databaseManager: databaseManager
        )

        // Initialize audio player service (long-lived singleton)
        self.audioPlayerService = AudioPlayerService(
            audioService: audioService,
            fileSystemService: fileSystemService,
            repository: recordingRepository
        )

        // Initialize import service
        self.importService = RecordingImportService(
            fileSystemService: fileSystemService,
            audioService: audioService,
            repository: recordingRepository
        )

        AppLogger.general.info("AppDependencyContainer initialized successfully")
    }
}

// MARK: - Environment Key

/// Environment key for accessing the dependency container
struct AppDependencyContainerKey: EnvironmentKey {
    static let defaultValue: AppDependencyContainer? = nil
}

extension EnvironmentValues {
    var container: AppDependencyContainer? {
        get { self[AppDependencyContainerKey.self] }
        set { self[AppDependencyContainerKey.self] = newValue }
    }
}

// MARK: - View Extension for Easy Access

extension View {
    /// Inject the dependency container into the environment
    func withDependencies(_ container: AppDependencyContainer) -> some View {
        environment(\.container, container)
    }
}

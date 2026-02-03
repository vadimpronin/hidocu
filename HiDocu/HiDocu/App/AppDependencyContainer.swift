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
    
    /// Device connection service - wraps JensenUSB (MUST stay alive)
    let deviceService: DeviceConnectionService
    
    /// Audio compatibility service - handles .hda format and validation
    let audioService: AudioCompatibilityService
    
    // MARK: - Repositories
    
    /// Recording repository for data access
    let recordingRepository: SQLiteRecordingRepository
    
    // MARK: - Sync Services
    
    /// Recording sync service - handles device-to-local synchronization
    let syncService: RecordingSyncService
    
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
        
        // Initialize device service (long-lived singleton)
        self.deviceService = DeviceConnectionService()
        
        // Initialize audio compatibility service
        self.audioService = AudioCompatibilityService()
        
        // Initialize repositories (with FileSystemService for path mapping)
        self.recordingRepository = SQLiteRecordingRepository(
            databaseManager: databaseManager,
            fileSystemService: fileSystemService
        )
        
        // Initialize sync service
        self.syncService = RecordingSyncService(
            deviceService: deviceService,
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

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
@MainActor
final class AppDependencyContainer {
    
    // MARK: - Services (Long-lived Singletons)
    
    /// Database manager - handles SQLite operations
    let databaseManager: DatabaseManager
    
    /// File system service - handles sandbox-compliant file operations
    let fileSystemService: FileSystemService
    
    /// Device manager - manages multiple device connections (MUST stay alive)
    let deviceManager: DeviceManager
    
    // MARK: - Repositories

    let folderRepository: SQLiteFolderRepository
    let documentRepository: SQLiteDocumentRepository
    let sourceRepository: SQLiteSourceRepository
    let transcriptRepository: SQLiteTranscriptRepository
    let recordingRepositoryV2: SQLiteRecordingRepositoryV2
    let deletionLogRepository: SQLiteDeletionLogRepository
    let llmAccountRepository: SQLiteLLMAccountRepository
    let apiLogRepository: SQLiteAPILogRepository

    // MARK: - Services

    let documentService: DocumentService
    let folderService: FolderService
    let contextService: ContextService
    let trashService: TrashService
    let settingsService: SettingsService
    let importServiceV2: RecordingImportServiceV2
    let keychainService: KeychainService
    let llmService: LLMService

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

        // Initialize repositories
        self.folderRepository = SQLiteFolderRepository(databaseManager: databaseManager)
        self.documentRepository = SQLiteDocumentRepository(databaseManager: databaseManager)
        self.sourceRepository = SQLiteSourceRepository(databaseManager: databaseManager)
        self.transcriptRepository = SQLiteTranscriptRepository(databaseManager: databaseManager)
        self.recordingRepositoryV2 = SQLiteRecordingRepositoryV2(databaseManager: databaseManager)
        self.deletionLogRepository = SQLiteDeletionLogRepository(databaseManager: databaseManager)
        self.llmAccountRepository = SQLiteLLMAccountRepository(databaseManager: databaseManager)
        self.apiLogRepository = SQLiteAPILogRepository(databaseManager: databaseManager)

        // Initialize services
        self.settingsService = SettingsService()
        self.keychainService = KeychainService()

        self.folderService = FolderService(
            folderRepository: folderRepository,
            documentRepository: documentRepository,
            sourceRepository: sourceRepository,
            transcriptRepository: transcriptRepository,
            fileSystemService: fileSystemService
        )

        self.documentService = DocumentService(
            documentRepository: documentRepository,
            sourceRepository: sourceRepository,
            transcriptRepository: transcriptRepository,
            deletionLogRepository: deletionLogRepository,
            folderRepository: folderRepository,
            fileSystemService: fileSystemService
        )

        self.contextService = ContextService(
            folderRepository: folderRepository,
            documentRepository: documentRepository,
            folderService: folderService
        )

        self.trashService = TrashService(
            deletionLogRepository: deletionLogRepository,
            documentRepository: documentRepository,
            folderRepository: folderRepository,
            fileSystemService: fileSystemService
        )

        self.importServiceV2 = RecordingImportServiceV2(
            fileSystemService: fileSystemService,
            repository: recordingRepositoryV2
        )

        self.llmService = LLMService(
            keychainService: keychainService,
            accountRepository: llmAccountRepository,
            apiLogRepository: apiLogRepository,
            documentService: documentService,
            settingsService: settingsService,
            claudeProvider: ClaudeProvider(),
            codexProvider: CodexProvider(),
            geminiProvider: GeminiProvider(),
            antigravityProvider: AntigravityProvider()
        )

        // Apply settings to file system service
        if let dataDir = settingsService.settings.general.dataDirectory {
            fileSystemService.setDataDirectory(URL(fileURLWithPath: dataDir))
        }

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

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
    let llmUsageRepository: SQLiteLLMUsageRepository
    let llmJobRepository: SQLiteLLMJobRepository
    let llmModelRepository: SQLiteLLMModelRepository
    let recordingSourceRepository: SQLiteRecordingSourceRepository

    // MARK: - Services

    let documentService: DocumentService
    let folderService: FolderService
    let contextService: ContextService
    let trashService: TrashService
    let settingsService: SettingsService
    let importServiceV2: RecordingImportServiceV2
    let keychainService: KeychainService
    let tokenManager: TokenManager
    let llmService: LLMService
    let quotaService: QuotaService
    let llmQueueState: LLMQueueState
    let llmQueueService: LLMQueueService
    let recordingSourceService: RecordingSourceService

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
        self.llmUsageRepository = SQLiteLLMUsageRepository(databaseManager: databaseManager)
        self.llmJobRepository = SQLiteLLMJobRepository(databaseManager: databaseManager)
        self.llmModelRepository = SQLiteLLMModelRepository(databaseManager: databaseManager)
        self.recordingSourceRepository = SQLiteRecordingSourceRepository(databaseManager: databaseManager)

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

        // Initialize provider strategies (shared between TokenManager and LLMService)
        let claudeProvider = ClaudeProvider()
        let codexProvider = CodexProvider()
        let geminiProvider = GeminiProvider()
        let antigravityProvider = AntigravityProvider()
        let providerMap: [LLMProvider: any LLMProviderStrategy] = [
            .claude: claudeProvider,
            .codex: codexProvider,
            .gemini: geminiProvider,
            .antigravity: antigravityProvider
        ]

        // TokenManager must be initialized before LLMService
        self.tokenManager = TokenManager(
            keychainService: keychainService,
            accountRepository: llmAccountRepository,
            providers: providerMap
        )

        // QuotaService must be initialized before LLMService
        self.quotaService = QuotaService(
            tokenManager: tokenManager,
            accountRepository: llmAccountRepository,
            usageRepository: llmUsageRepository
        )

        // LLMService must be initialized before importServiceV2 (which depends on it)
        self.llmService = LLMService(
            tokenManager: tokenManager,
            keychainService: keychainService,
            accountRepository: llmAccountRepository,
            apiLogRepository: apiLogRepository,
            modelRepository: llmModelRepository,
            documentService: documentService,
            settingsService: settingsService,
            quotaService: quotaService,
            claudeProvider: claudeProvider,
            codexProvider: codexProvider,
            geminiProvider: geminiProvider,
            antigravityProvider: antigravityProvider
        )

        // Initialize LLM queue state and service (must be before importServiceV2)
        self.llmQueueState = LLMQueueState()
        self.llmQueueService = LLMQueueService(
            jobRepository: llmJobRepository,
            accountRepository: llmAccountRepository,
            llmService: llmService,
            quotaService: quotaService,
            transcriptRepository: transcriptRepository,
            documentService: documentService,
            fileSystemService: fileSystemService,
            settingsService: settingsService,
            state: llmQueueState
        )

        // Wire LLMQueueService into DocumentService (post-init to break circular dependency)
        documentService.setLLMQueueService(llmQueueService)

        // Initialize RecordingSourceService (must be before importServiceV2)
        self.recordingSourceService = RecordingSourceService(
            recordingSourceRepository: recordingSourceRepository,
            recordingRepository: recordingRepositoryV2,
            fileSystemService: fileSystemService
        )

        self.importServiceV2 = RecordingImportServiceV2(
            fileSystemService: fileSystemService,
            documentService: documentService,
            sourceRepository: sourceRepository,
            transcriptRepository: transcriptRepository,
            llmService: llmService,
            llmQueueService: llmQueueService,
            settingsService: settingsService,
            recordingSourceService: recordingSourceService,
            recordingRepository: recordingRepositoryV2
        )

        // Bootstrap "Imported" source so it always appears in the sidebar
        Task {
            do {
                _ = try await recordingSourceService.ensureImportSource()
            } catch {
                AppLogger.database.error("Failed to bootstrap Imported source: \(error.localizedDescription)")
            }
        }

        // Wire RecordingSourceService into DeviceManager (post-init)
        deviceManager.setRecordingSourceService(recordingSourceService)

        // Apply settings to file system service
        if let dataDir = settingsService.settings.general.dataDirectory {
            fileSystemService.setDataDirectory(URL(fileURLWithPath: dataDir))
        }

        // Backfill audio_path for existing sources that were created before v11
        Self.backfillSourceAudioPaths(
            sourceRepository: sourceRepository,
            fileSystemService: fileSystemService
        )

        // Start periodic quota refresh
        quotaService.startPeriodicRefresh()

        // Start USB monitoring AFTER all services are wired
        deviceManager.startMonitoring()

        // Start LLM queue processor
        Task {
            await llmQueueService.startProcessing()
        }

        AppLogger.general.info("AppDependencyContainer initialized successfully")
    }

    // MARK: - Backfill

    /// One-time backfill: populate `audio_path` on sources that lack it
    /// by reading each source's `source.yaml` from disk.
    private static func backfillSourceAudioPaths(
        sourceRepository: SQLiteSourceRepository,
        fileSystemService: FileSystemService
    ) {
        do {
            let allSources = try sourceRepository.fetchAllSync()
            var backfilled = 0
            for var source in allSources where source.audioPath == nil {
                if let audioPath = fileSystemService.readSourceAudioPath(sourceDiskPath: source.diskPath) {
                    source.audioPath = audioPath
                    try sourceRepository.updateSync(source)
                    backfilled += 1
                }
            }
            if backfilled > 0 {
                AppLogger.database.info("Backfilled audio_path for \(backfilled) source(s)")
            }
        } catch {
            AppLogger.database.error("Failed to backfill source audio paths: \(error.localizedDescription)")
        }
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

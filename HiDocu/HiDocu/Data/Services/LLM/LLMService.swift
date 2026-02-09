//
//  LLMService.swift
//  HiDocu
//
//  Main facade service for all LLM operations.
//  Manages accounts, token lifecycle, and summary generation.
//

import Foundation

@Observable
@MainActor
final class LLMService {

    // MARK: - Dependencies

    private let tokenManager: TokenManager
    private let keychainService: KeychainService
    private let accountRepository: any LLMAccountRepository
    private let apiLogRepository: any APILogRepository
    private let modelRepository: any LLMModelRepository
    private let documentService: DocumentService
    private let settingsService: SettingsService
    private let quotaService: QuotaService

    // MARK: - Provider Registry

    private let providers: [LLMProvider: any LLMProviderStrategy]

    // MARK: - Model Cache

    /// Cached available models across all providers, sorted by provider then model name.
    private(set) var availableModels: [AvailableModel] = []

    /// Guard against concurrent refresh calls.
    private var isRefreshingModels = false

    /// Tracks whether a refresh was requested while one was in progress.
    private var pendingRefresh = false

    // MARK: - Round-Robin State

    private var roundRobinCounters: [LLMProvider: Int] = [:]

    // MARK: - Initialization

    init(
        tokenManager: TokenManager,
        keychainService: KeychainService,
        accountRepository: any LLMAccountRepository,
        apiLogRepository: any APILogRepository,
        modelRepository: any LLMModelRepository,
        documentService: DocumentService,
        settingsService: SettingsService,
        quotaService: QuotaService,
        claudeProvider: any LLMProviderStrategy,
        codexProvider: any LLMProviderStrategy,
        geminiProvider: any LLMProviderStrategy,
        antigravityProvider: any LLMProviderStrategy
    ) {
        self.tokenManager = tokenManager
        self.keychainService = keychainService
        self.accountRepository = accountRepository
        self.apiLogRepository = apiLogRepository
        self.modelRepository = modelRepository
        self.documentService = documentService
        self.settingsService = settingsService
        self.quotaService = quotaService

        self.providers = [
            .claude: claudeProvider,
            .codex: codexProvider,
            .gemini: geminiProvider,
            .antigravity: antigravityProvider
        ]
    }

    // MARK: - Account Management

    /// Adds a new LLM account by initiating OAuth authentication.
    /// - Parameter provider: The provider to authenticate with
    /// - Returns: The created account
    /// - Throws: `LLMError` if authentication or storage fails
    func addAccount(provider: LLMProvider) async throws -> LLMAccount {
        AppLogger.llm.info("Adding new account for provider: \(provider.rawValue)")

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        // Authenticate and get token bundle
        let tokenBundle = try await strategy.authenticate()

        // Check if account already exists for this provider + email
        let existing = try await accountRepository.fetchByProviderAndEmail(
            provider: provider,
            email: tokenBundle.email
        )

        let account: LLMAccount
        if let existing {
            // Update existing account
            AppLogger.llm.info("Account already exists for \(provider.rawValue) \(tokenBundle.email), updating")
            var updated = existing
            updated.isActive = true
            updated.lastUsedAt = Date()
            try await accountRepository.update(updated)
            account = updated
        } else {
            // Create new account
            let newAccount = LLMAccount(
                id: 0,
                provider: provider,
                email: tokenBundle.email,
                displayName: tokenBundle.email,
                isActive: true,
                lastUsedAt: nil,
                createdAt: Date()
            )
            account = try await accountRepository.insert(newAccount)
            AppLogger.llm.info("Created new account id=\(account.id) for \(provider.rawValue) \(tokenBundle.email)")
        }

        // Save tokens to keychain
        let tokenData = TokenData(
            accessToken: tokenBundle.accessToken,
            refreshToken: tokenBundle.refreshToken,
            expiresAt: tokenBundle.expiresAt,
            idToken: tokenBundle.idToken,
            accountId: tokenBundle.accountId,
            projectId: tokenBundle.projectId,
            clientId: nil,
            clientSecret: tokenBundle.clientSecret
        )
        try keychainService.saveToken(tokenData, identifier: account.keychainIdentifier)

        AppLogger.llm.info("Successfully added account id=\(account.id) for \(provider.rawValue)")
        await refreshAvailableModels()
        return account
    }

    /// Removes an LLM account and deletes its tokens.
    /// - Parameter id: Account ID to remove
    /// - Throws: Database or keychain errors
    func removeAccount(id: Int64) async throws {
        AppLogger.llm.info("Removing account id=\(id)")

        guard let account = try await accountRepository.fetchById(id) else {
            AppLogger.llm.warning("Account id=\(id) not found, skipping removal")
            return
        }

        // Delete keychain token (ignore errors if not found)
        try? keychainService.deleteToken(identifier: account.keychainIdentifier)

        // Delete from database
        try await accountRepository.delete(id: id)

        AppLogger.llm.info("Successfully removed account id=\(id)")
        await refreshAvailableModels()
    }

    /// Lists all configured LLM accounts.
    /// - Returns: Array of all accounts
    func listAccounts() async throws -> [LLMAccount] {
        try await accountRepository.fetchAll()
    }

    /// Lists accounts for a specific provider.
    /// - Parameter provider: Provider to filter by
    /// - Returns: Array of accounts for the provider
    func listAccounts(provider: LLMProvider) async throws -> [LLMAccount] {
        try await accountRepository.fetchAll(provider: provider)
    }

    // MARK: - Model Fetching

    /// Fetches available models for a provider.
    /// - Parameter provider: Provider to fetch models from
    /// - Returns: Array of model identifiers
    /// - Throws: `LLMError` if no accounts are configured or API call fails
    func fetchModels(provider: LLMProvider) async throws -> [ModelInfo] {
        AppLogger.llm.info("Fetching models for \(provider.rawValue)")

        // Use any account for this provider (including rate-limited ones)
        // since model listing is not subject to generation rate limits
        let accounts = try await accountRepository.fetchAll(provider: provider)
        guard let account = accounts.first(where: { $0.isActive }) ?? accounts.first else {
            throw LLMError.noAccountsConfigured(provider)
        }

        // Get valid access token and token data (single keychain load)
        let (accessToken, tokenData) = try await tokenManager.getValidAccessToken(for: account)

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        // Fetch models from provider
        let models = try await strategy.fetchModels(accessToken: accessToken, accountId: tokenData.accountId, tokenData: tokenData)
        AppLogger.llm.info("Fetched \(models.count) models for \(provider.rawValue)")
        return models
    }

    /// Refreshes the cached list of available models from all providers.
    /// Fetches from ALL active accounts per provider, syncs results to the database,
    /// then reloads the in-memory cache from DB.
    /// Silently skips providers with no configured accounts.
    /// Deduplicates concurrent calls — only one refresh runs at a time.
    func refreshAvailableModels() async {
        guard !isRefreshingModels else {
            pendingRefresh = true
            return
        }
        isRefreshingModels = true
        defer {
            isRefreshingModels = false
            if pendingRefresh {
                pendingRefresh = false
                Task { await refreshAvailableModels() }
            }
        }
        AppLogger.llm.info("Refreshing available models from all accounts")

        for provider in LLMProvider.allCases {
            do {
                let accountResults = try await fetchModelsFromAllAccounts(provider: provider)
                for result in accountResults {
                    try await modelRepository.syncModelsForAccount(
                        accountId: result.accountId,
                        provider: provider,
                        fetchedModels: result.models
                    )
                }
            } catch let error as LLMError {
                if case .noAccountsConfigured = error { /* skip */ }
                else { AppLogger.llm.warning("Failed to refresh models for \(provider.rawValue): \(error.localizedDescription)") }
            } catch {
                AppLogger.llm.warning("Failed to refresh models for \(provider.rawValue): \(error.localizedDescription)")
            }
        }

        // Reload from DB after sync
        await reloadModelsFromDB()
    }

    /// Loads the available models from the database (fast, no API calls).
    /// Call on startup for instant display, and after each API refresh.
    func reloadModelsFromDB() async {
        do {
            availableModels = try await modelRepository.fetchAllAvailableModels()
            AppLogger.llm.info("Loaded \(self.availableModels.count) models from DB")
        } catch {
            AppLogger.llm.error("Failed to load models from DB: \(error.localizedDescription)")
        }
    }

    /// Fetches models from ALL active accounts for a provider.
    /// Tolerates individual account failures — logs warnings and continues.
    private func fetchModelsFromAllAccounts(provider: LLMProvider) async throws -> [(accountId: Int64, models: [ModelInfo])] {
        let accounts = try await accountRepository.fetchAll(provider: provider)
        let activeAccounts = accounts.filter { $0.isActive }
        guard !activeAccounts.isEmpty else {
            throw LLMError.noAccountsConfigured(provider)
        }

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        var results: [(accountId: Int64, models: [ModelInfo])] = []
        for account in activeAccounts {
            do {
                let (accessToken, tokenData) = try await tokenManager.getValidAccessToken(for: account)
                let models = try await strategy.fetchModels(
                    accessToken: accessToken, accountId: tokenData.accountId, tokenData: tokenData
                )
                results.append((accountId: account.id, models: models))
            } catch {
                AppLogger.llm.warning("Failed to fetch models for account \(account.id) (\(provider.rawValue)): \(error.localizedDescription)")
            }
        }
        return results
    }

    // MARK: - Summary Generation

    /// Generates a summary for a document using configured LLM settings.
    /// - Parameters:
    ///   - document: Document to summarize
    ///   - modelOverride: Optional provider:model override (e.g., "claude:claude-3-5-sonnet-20241022")
    /// - Returns: LLM response with generated summary
    /// - Throws: `LLMError` if generation fails
    func generateSummary(for document: Document, modelOverride: String? = nil) async throws -> LLMResponse {
        let startTime = Date()
        AppLogger.llm.info("Generating summary for document id=\(document.id)")

        // Read document body
        let body: String
        do {
            body = try documentService.readBody(diskPath: document.diskPath)
        } catch {
            AppLogger.llm.error("Failed to read document body: \(error.localizedDescription)")
            throw LLMError.documentNotFound
        }

        // Determine provider and model
        let provider: LLMProvider
        let model: String
        if let override = modelOverride {
            let parts = override.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                throw LLMError.authenticationFailed(
                    provider: .claude,
                    detail: "Invalid modelOverride format: \(override)"
                )
            }
            guard let providerValue = LLMProvider(rawValue: String(parts[0])) else {
                throw LLMError.authenticationFailed(
                    provider: .claude,
                    detail: "Invalid provider in override: \(parts[0])"
                )
            }
            provider = providerValue
            model = String(parts[1])
        } else {
            let settings = settingsService.settings.llm
            guard let providerRawValue = LLMProvider(rawValue: settings.defaultProvider) else {
                throw LLMError.authenticationFailed(
                    provider: .claude,
                    detail: "Invalid default provider: \(settings.defaultProvider)"
                )
            }
            provider = providerRawValue
            model = settings.defaultModel.isEmpty ? "claude-3-5-sonnet-20241022" : settings.defaultModel
        }
        let promptTemplate = settingsService.settings.llm.summaryPromptTemplate

        // Replace template placeholders
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        let summaryPrompt = promptTemplate
            .replacingOccurrences(of: "{{document_body}}", with: body)
            .replacingOccurrences(of: "{{document_title}}", with: document.title)
            .replacingOccurrences(of: "{{current_date}}", with: dateFormatter.string(from: Date()))

        // Select account
        let account = try await selectAccount(provider: provider)

        // Get valid access token and token data (single keychain load)
        let (accessToken, currentTokenData) = try await tokenManager.getValidAccessToken(for: account)

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        let messages = [
            LLMMessage(role: .user, content: summaryPrompt)
        ]

        let options = LLMRequestOptions(
//            maxTokens: 4096,
            temperature: nil,
//            systemPrompt: systemPrompt
        )

        // Make API call with retry on 401
        let response: LLMResponse
        do {
            response = try await strategy.chat(
                messages: messages,
                model: model,
                accessToken: accessToken,
                options: options,
                tokenData: currentTokenData
            )
        } catch let error as LLMError {
            // On rate limit, record in quota service and rethrow
            if case .rateLimited(_, let retryAfter) = error {
                await quotaService.recordRateLimit(accountId: account.id, provider: provider, retryAfter: retryAfter)
                logSummaryError(error: error, account: account, model: model, startTime: startTime, documentId: document.id)
                throw error
            }
            // On 401, refresh token once and retry
            if case .apiError(_, let statusCode, _) = error, statusCode == 401 {
                AppLogger.llm.warning("Received 401, refreshing token and retrying")
                let (newAccessToken, refreshedTokenData) = try await tokenManager.refreshAndGetToken(for: account)
                response = try await strategy.chat(
                    messages: messages,
                    model: model,
                    accessToken: newAccessToken,
                    options: options,
                    tokenData: refreshedTokenData
                )
            } else {
                logSummaryError(error: error, account: account, model: model, startTime: startTime, documentId: document.id)
                throw error
            }
        }

        // Save summary to disk with metadata
        do {
            try await documentService.writeSummary(
                documentId: document.id,
                diskPath: document.diskPath,
                content: response.content,
                model: "\(provider.rawValue):\(response.model)",
                generatedAt: Date(),
                edited: false
            )
            AppLogger.llm.info("Saved summary for document id=\(document.id)")
        } catch {
            AppLogger.llm.error("Failed to save summary: \(error.localizedDescription)")
        }

        // Update account last used
        try await accountRepository.updateLastUsed(id: account.id)

        // Record usage
        await quotaService.recordUsage(
            accountId: account.id,
            modelId: model,
            inputTokens: response.inputTokens ?? 0,
            outputTokens: response.outputTokens ?? 0
        )

        // Log API call
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let logEntry = APILogEntry(
            id: 0,
            provider: provider,
            llmAccountId: account.id,
            model: response.model,
            requestPayload: truncatePayload(summaryPrompt, maxBytes: 10_000),
            responsePayload: truncatePayload(response.content, maxBytes: 10_000),
            timestamp: Date(),
            documentId: document.id,
            sourceId: nil,
            transcriptId: nil,
            status: "success",
            error: nil,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            durationMs: duration
        )
        _ = try? await apiLogRepository.insert(logEntry)

        AppLogger.llm.info("Summary generated successfully for document id=\(document.id)")
        return response
    }

    /// Logs a failed summary API request.
    private func logSummaryError(
        error: Error,
        account: LLMAccount,
        model: String,
        startTime: Date,
        documentId: Int64
    ) {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let status: String
        let errorMessage: String

        if let llmError = error as? LLMError {
            switch llmError {
            case .rateLimited:
                status = "rate_limited"
                errorMessage = llmError.localizedDescription
            default:
                status = "error"
                errorMessage = llmError.localizedDescription
            }
        } else {
            status = "error"
            errorMessage = error.localizedDescription
        }

        let logEntry = APILogEntry(
            id: 0,
            provider: account.provider,
            llmAccountId: account.id,
            model: model,
            requestPayload: "[summary generation]",
            responsePayload: extractResponseBody(from: error),
            timestamp: Date(),
            documentId: documentId,
            sourceId: nil,
            transcriptId: nil,
            status: status,
            error: errorMessage,
            inputTokens: nil,
            outputTokens: nil,
            durationMs: duration
        )
        Task {
            do {
                _ = try await apiLogRepository.insert(logEntry)
            } catch {
                AppLogger.llm.warning("Failed to insert API log: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Audio Transcription

    /// MIME type mapping for audio file extensions.
    private static let audioMimeTypes: [String: String] = [
        "hda": "audio/mpeg",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "wav": "audio/wav",
        "aac": "audio/aac",
        "ogg": "audio/ogg",
        "flac": "audio/flac",
        "opus": "audio/opus",
        "aiff": "audio/aiff"
    ]

    /// Maximum inline data size for Gemini API (conservative limit leaving room for prompt).
//    private static let maxInlineDataSize = 18 * 1024 * 1024 // 18 MB

    /// Prepares audio attachments from sources for transcription.
    ///
    /// Loads audio data and validates total size. This method is called once
    /// by the ViewModel and the result is shared across parallel transcript generation calls.
    ///
    /// - Parameters:
    ///   - sources: Sources with recording details
    ///   - fileSystemService: File system service to resolve file paths
    /// - Returns: Array of LLM attachments with audio data
    /// - Throws: `LLMError` if audio files are missing or exceed size limit
    func prepareAudioAttachments(
        sources: [SourceWithDetails],
        fileSystemService: FileSystemService
    ) throws -> [LLMAttachment] {
        var attachments: [LLMAttachment] = []
        var totalSize: Int = 0

        for source in sources {
            // Resolve audio path: DB audioPath → RecordingV2 filepath → source.yaml fallback
            let audioRelativePath: String
            let displayName: String

            if let dbPath = source.source.audioPath {
                audioRelativePath = dbPath
                displayName = source.source.displayName ?? (dbPath as NSString).lastPathComponent
            } else if let recording = source.recording {
                audioRelativePath = recording.filepath
                displayName = recording.filename
            } else if let yamlPath = fileSystemService.readSourceAudioPath(sourceDiskPath: source.source.diskPath) {
                audioRelativePath = yamlPath
                displayName = source.source.displayName ?? (yamlPath as NSString).lastPathComponent
            } else {
                AppLogger.llm.warning("Source \(source.id) has no audio path, skipping")
                continue
            }

            // Audio files live under dataDirectory (~/HiDocu), not storageDirectory
            let fileURL = fileSystemService.dataDirectory
                .appendingPathComponent(audioRelativePath)

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                AppLogger.llm.error("Audio file not found: \(fileURL.path)")
                throw LLMError.invalidResponse(detail: "Audio file not found: \(displayName)")
            }

            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileURL)
            } catch {
                AppLogger.llm.error("Failed to read audio file: \(error.localizedDescription)")
                throw LLMError.invalidResponse(detail: "Failed to read audio file: \(displayName)")
            }

            totalSize += fileData.count

            let ext = fileURL.pathExtension.lowercased()
            let mimeType = Self.audioMimeTypes[ext] ?? "audio/mpeg"
            attachments.append(LLMAttachment(data: fileData, mimeType: mimeType))
        }

        guard !attachments.isEmpty else {
            throw LLMError.invalidResponse(detail: "No audio files found in sources")
        }

        let sizeMBLog = Double(totalSize) / (1024 * 1024)
        AppLogger.llm.info("Loaded \(attachments.count) audio file(s), total \(String(format: "%.1f", sizeMBLog)) MB")

//        if totalSize > Self.maxInlineDataSize {
//            let sizeMB = totalSize / (1024 * 1024)
//            throw LLMError.invalidResponse(
//                detail: "Audio files total \(sizeMB) MB, exceeding the 18 MB inline limit. Use shorter recordings."
//            )
//        }

        return attachments
    }

    /// Convenience overload of `prepareAudioAttachments` that accepts `[Source]` instead of `[SourceWithDetails]`.
    /// - Parameters:
    ///   - sources: Array of sources to prepare attachments from
    ///   - fileSystemService: File system service to resolve file paths
    /// - Returns: Array of LLM attachments with audio data
    /// - Throws: `LLMError` if audio files are missing or exceed size limit
    func prepareAudioAttachments(sources: [Source], fileSystemService: FileSystemService) throws -> [LLMAttachment] {
        let wrapped = sources.map { SourceWithDetails(source: $0, recording: nil, transcripts: []) }
        return try prepareAudioAttachments(sources: wrapped, fileSystemService: fileSystemService)
    }

    /// Generates a single audio transcript using Gemini multimodal API.
    ///
    /// - Parameters:
    ///   - attachments: Pre-loaded audio attachments
    ///   - model: Gemini model identifier
    ///   - transcriptId: Transcript ID for API log linking
    ///   - documentId: Document ID for API log linking
    ///   - sourceId: Source ID for API log linking
    /// - Returns: Transcript text
    /// - Throws: `LLMError` if generation fails
    func generateSingleTranscript(
        attachments: [LLMAttachment],
        model: String,
        transcriptId: Int64,
        documentId: Int64?,
        sourceId: Int64?
    ) async throws -> String {
        let startTime = Date()
        AppLogger.llm.info("Generating transcript for transcriptId=\(transcriptId) using model: \(model)")

        let prompt = """
            Transcribe this audio of an interview in a mix of Russian and English.
            Do not try to save tokens in output by dropping some parts of the conversation. Be exact to the word, include everything that's being said. Do not skip anything.
            Ideal response will contain full transcript of the audio with properly identified speakers.
            """

        let message = LLMMessage(role: .user, content: prompt, attachments: attachments)
        let messages = [message]
        let options = LLMRequestOptions(temperature: nil)

        // Select Gemini account and get credentials
        let account = try await selectAccount(provider: .gemini)

        guard let strategy = providers[.gemini] else {
            throw LLMError.authenticationFailed(provider: .gemini, detail: "Gemini provider not configured")
        }

        // Helper: single chat call with 401 retry and rate-limit recording
        let chatWithRetry: () async throws -> LLMResponse = {
            let (accessToken, tokenData) = try await self.tokenManager.getValidAccessToken(for: account)
            do {
                return try await strategy.chat(
                    messages: messages, model: model, accessToken: accessToken,
                    options: options, tokenData: tokenData
                )
            } catch let error as LLMError {
                if case .rateLimited(_, let retryAfter) = error {
                    await self.quotaService.recordRateLimit(accountId: account.id, provider: .gemini, retryAfter: retryAfter)
                    throw error
                }
                if case .apiError(_, let statusCode, _) = error, statusCode == 401 {
                    AppLogger.llm.warning("Received 401 during transcription, refreshing token and retrying")
                    let (newToken, refreshedData) = try await self.tokenManager.refreshAndGetToken(for: account)
                    return try await strategy.chat(
                        messages: messages, model: model, accessToken: newToken,
                        options: options, tokenData: refreshedData
                    )
                }
                throw error
            }
        }

        do {
            let response = try await chatWithRetry()
            try await accountRepository.updateLastUsed(id: account.id)

            // Record usage
            await quotaService.recordUsage(
                accountId: account.id,
                modelId: model,
                inputTokens: response.inputTokens ?? 0,
                outputTokens: response.outputTokens ?? 0
            )

            // Log successful request
            logTranscriptionRequest(
                response: response,
                account: account,
                startTime: startTime,
                model: model,
                transcriptId: transcriptId,
                documentId: documentId,
                sourceId: sourceId
            )

            AppLogger.llm.info("Generated transcript for transcriptId=\(transcriptId)")
            return response.content
        } catch {
            // Log error before rethrowing
            logTranscriptionError(
                error: error,
                account: account,
                model: model,
                startTime: startTime,
                transcriptId: transcriptId,
                documentId: documentId,
                sourceId: sourceId
            )
            throw error
        }
    }

    /// Logs a successful transcription API request.
    private func logTranscriptionRequest(
        response: LLMResponse,
        account: LLMAccount,
        startTime: Date,
        model: String,
        transcriptId: Int64,
        documentId: Int64?,
        sourceId: Int64?
    ) {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let logEntry = APILogEntry(
            id: 0,
            provider: .gemini,
            llmAccountId: account.id,
            model: model,
            requestPayload: "[audio transcription]",
            responsePayload: truncatePayload(response.content, maxBytes: 10_000),
            timestamp: Date(),
            documentId: documentId,
            sourceId: sourceId,
            transcriptId: transcriptId,
            status: "success",
            error: nil,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            durationMs: duration
        )
        Task {
            do {
                _ = try await apiLogRepository.insert(logEntry)
            } catch {
                AppLogger.llm.warning("Failed to insert API log: \(error.localizedDescription)")
            }
        }
    }

    /// Logs a failed transcription API request.
    private func logTranscriptionError(
        error: Error,
        account: LLMAccount,
        model: String,
        startTime: Date,
        transcriptId: Int64,
        documentId: Int64?,
        sourceId: Int64?
    ) {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let status: String
        let errorMessage: String

        if let llmError = error as? LLMError {
            switch llmError {
            case .rateLimited:
                status = "rate_limited"
                errorMessage = llmError.localizedDescription
            default:
                status = "error"
                errorMessage = llmError.localizedDescription
            }
        } else {
            status = "error"
            errorMessage = error.localizedDescription
        }

        let logEntry = APILogEntry(
            id: 0,
            provider: .gemini,
            llmAccountId: account.id,
            model: model,
            requestPayload: "[audio transcription]",
            responsePayload: extractResponseBody(from: error),
            timestamp: Date(),
            documentId: documentId,
            sourceId: sourceId,
            transcriptId: transcriptId,
            status: status,
            error: errorMessage,
            inputTokens: nil,
            outputTokens: nil,
            durationMs: duration
        )
        Task {
            do {
                _ = try await apiLogRepository.insert(logEntry)
            } catch {
                AppLogger.llm.warning("Failed to insert API log: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Transcript Evaluation

    /// Evaluates multiple transcript variants and returns a judge response identifying the best one.
    func evaluateTranscripts(
        transcripts: [Transcript],
        documentId: Int64,
        provider: LLMProvider = .gemini,
        model: String = "gemini-3-pro-preview" // TODO: use settings.llm.judgeModel when configurable
    ) async throws -> JudgeResponse {
        let startTime = Date()
        AppLogger.llm.info("Evaluating \(transcripts.count) transcripts for document \(documentId)")

        // Filter transcripts with valid text
        let minTextLength = 50
        var indexToTranscriptId: [Int64: Int64] = [:] // promptIndex -> transcriptId
        var promptParts: [String] = []
        var promptIndex: Int64 = 1

        for transcript in transcripts {
            guard let text = transcript.fullText,
                  text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minTextLength else {
                AppLogger.llm.info("Skipping transcript \(transcript.id) from evaluation (empty or too short)")
                continue
            }
            indexToTranscriptId[promptIndex] = transcript.id
            promptParts.append("<transcript id=\"\(promptIndex)\">\n\(text)\n</transcript>")
            promptIndex += 1
        }

        guard indexToTranscriptId.count >= 2 else {
            throw LLMError.invalidResponse(detail: "Need at least 2 valid transcripts to evaluate, got \(indexToTranscriptId.count)")
        }

        let prompt = """
            Compare \(indexToTranscriptId.count) transcripts:

            \(promptParts.joined(separator: "\n\n"))

            One of them is odd, may contain mistakes, hallucinations or have some information missing or wrongly identified speakers.
            Which one is odd?
            And which one is the best?
            Respond in json like this:
            {
              "reasoning_about_the_odd_one": "<reasoning>",
              "odd_id": <number>,
              "reasoning_about_the_best_one": "<reasoning>",
              "best_id": <number>
            }
            """

        // Select account
        let account = try await selectAccount(provider: provider)

        // Get valid access token
        let (accessToken, currentTokenData) = try await tokenManager.getValidAccessToken(for: account)

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        let messages = [LLMMessage(role: .user, content: prompt)]
        let options = LLMRequestOptions(temperature: nil)

        // Make API call with retry on 401
        let response: LLMResponse
        do {
            response = try await strategy.chat(
                messages: messages,
                model: model,
                accessToken: accessToken,
                options: options,
                tokenData: currentTokenData
            )
        } catch let error as LLMError {
            if case .rateLimited(_, let retryAfter) = error {
                await quotaService.recordRateLimit(accountId: account.id, provider: provider, retryAfter: retryAfter)
                logEvaluationError(error: error, account: account, model: model, startTime: startTime, documentId: documentId)
                throw error
            }
            if case .apiError(_, let statusCode, _) = error, statusCode == 401 {
                AppLogger.llm.warning("Received 401 during transcript evaluation, refreshing token and retrying")
                let (newAccessToken, refreshedTokenData) = try await tokenManager.refreshAndGetToken(for: account)
                response = try await strategy.chat(
                    messages: messages,
                    model: model,
                    accessToken: newAccessToken,
                    options: options,
                    tokenData: refreshedTokenData
                )
            } else {
                logEvaluationError(error: error, account: account, model: model, startTime: startTime, documentId: documentId)
                throw error
            }
        }

        try await accountRepository.updateLastUsed(id: account.id)

        // Record usage
        await quotaService.recordUsage(
            accountId: account.id,
            modelId: model,
            inputTokens: response.inputTokens ?? 0,
            outputTokens: response.outputTokens ?? 0
        )

        // Extract and decode JSON
        guard let jsonString = extractJSON(from: response.content) else {
            let error = LLMError.invalidResponse(detail: "No JSON found in judge response")
            logEvaluationError(error: error, account: account, model: model, startTime: startTime, documentId: documentId)
            throw error
        }

        let decoded: JudgeResponse
        do {
            let data = Data(jsonString.utf8)
            decoded = try JSONDecoder().decode(JudgeResponse.self, from: data)
        } catch {
            AppLogger.llm.error("Failed to decode judge response: \(error.localizedDescription)\nRaw: \(String(response.content.prefix(500)))")
            let llmError = LLMError.invalidResponse(detail: "Failed to decode judge response: \(error.localizedDescription)")
            logEvaluationError(error: llmError, account: account, model: model, startTime: startTime, documentId: documentId)
            throw llmError
        }

        // Map prompt indices back to DB IDs
        guard let bestDbId = indexToTranscriptId[decoded.bestId],
              let oddDbId = indexToTranscriptId[decoded.oddId] else {
            let error = LLMError.invalidResponse(detail: "Judge returned IDs not in transcript set: bestId=\(decoded.bestId), oddId=\(decoded.oddId)")
            logEvaluationError(error: error, account: account, model: model, startTime: startTime, documentId: documentId)
            throw error
        }

        let result = JudgeResponse(
            oddReasoning: decoded.oddReasoning,
            oddId: oddDbId,
            bestReasoning: decoded.bestReasoning,
            bestId: bestDbId
        )

        // Log reasoning
        AppLogger.llm.info("Judge evaluation for document \(documentId): bestId=\(result.bestId), oddId=\(result.oddId)")
        AppLogger.llm.info("Best reasoning: \(result.bestReasoning)")
        AppLogger.llm.info("Odd reasoning: \(result.oddReasoning)")

        // Log API call
        logEvaluationRequest(response: response, account: account, startTime: startTime, model: model, documentId: documentId)

        return result
    }

    /// Extracts the first JSON object from a string, handling markdown code blocks.
    private func extractJSON(from text: String) -> String? {
        // Try to extract JSON from ```json ... ``` or ``` ... ``` code blocks using capture group
        let pattern = "```(?:json)?\\s*\\n?(\\{[\\s\\S]*?\\})\\s*\\n?```"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }

        // Fallback: find the first { ... last } block
        guard let startIdx = text.firstIndex(of: "{"),
              let endIdx = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[startIdx...endIdx])
    }

    /// Logs a successful evaluation API request.
    private func logEvaluationRequest(
        response: LLMResponse,
        account: LLMAccount,
        startTime: Date,
        model: String,
        documentId: Int64
    ) {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let logEntry = APILogEntry(
            id: 0,
            provider: account.provider,
            llmAccountId: account.id,
            model: model,
            requestPayload: "[transcript evaluation]",
            responsePayload: truncatePayload(response.content, maxBytes: 10_000),
            timestamp: Date(),
            documentId: documentId,
            sourceId: nil,
            transcriptId: nil,
            status: "success",
            error: nil,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            durationMs: duration
        )
        Task {
            do {
                _ = try await apiLogRepository.insert(logEntry)
            } catch {
                AppLogger.llm.warning("Failed to insert API log: \(error.localizedDescription)")
            }
        }
    }

    /// Logs a failed evaluation API request.
    private func logEvaluationError(
        error: Error,
        account: LLMAccount,
        model: String,
        startTime: Date,
        documentId: Int64
    ) {
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)
        let status: String
        let errorMessage: String

        if let llmError = error as? LLMError {
            switch llmError {
            case .rateLimited:
                status = "rate_limited"
                errorMessage = llmError.localizedDescription
            default:
                status = "error"
                errorMessage = llmError.localizedDescription
            }
        } else {
            status = "error"
            errorMessage = error.localizedDescription
        }

        let logEntry = APILogEntry(
            id: 0,
            provider: account.provider,
            llmAccountId: account.id,
            model: model,
            requestPayload: "[transcript evaluation]",
            responsePayload: extractResponseBody(from: error),
            timestamp: Date(),
            documentId: documentId,
            sourceId: nil,
            transcriptId: nil,
            status: status,
            error: errorMessage,
            inputTokens: nil,
            outputTokens: nil,
            durationMs: duration
        )
        Task {
            do {
                _ = try await apiLogRepository.insert(logEntry)
            } catch {
                AppLogger.llm.warning("Failed to insert API log: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Account Availability

    /// Checks if any active accounts are configured for the provider.
    /// - Parameter provider: Provider to check
    /// - Returns: True if at least one active account exists
    func hasActiveAccounts(for provider: LLMProvider) async -> Bool {
        do {
            let accounts = try await accountRepository.fetchActive(provider: provider)
            return !accounts.isEmpty
        } catch {
            AppLogger.llm.error("Failed to check active accounts for \(provider.rawValue): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Account Selection (Private)

    /// Selects an account for the provider using quota-aware selection with round-robin fallback.
    /// - Parameter provider: Provider to select account for
    /// - Returns: Selected account
    /// - Throws: `LLMError.allAccountsExhausted` if all accounts are paused or no accounts available
    private func selectAccount(provider: LLMProvider) async throws -> LLMAccount {
        // Get active accounts (already filters paused_until > now via repository)
        let accounts = try await accountRepository.fetchActive(provider: provider)

        guard !accounts.isEmpty else {
            throw LLMError.allAccountsExhausted(provider)
        }

        // Try quota-aware selection first
        if let bestAccount = await quotaService.bestAccount(for: provider) {
            // Verify this account is in the active accounts list
            if accounts.contains(where: { $0.id == bestAccount.id }) {
                AppLogger.llm.info("Selected best-quota account id=\(bestAccount.id) for \(provider.rawValue)")
                return bestAccount
            }
        }

        // Fallback to round-robin if no quota data
        let counter = roundRobinCounters[provider, default: 0]
        let selectedIndex = counter % accounts.count
        let selected = accounts[selectedIndex]
        roundRobinCounters[provider] = counter + 1

        AppLogger.llm.info("Selected account id=\(selected.id) for \(provider.rawValue) (round-robin fallback: \(counter))")
        return selected
    }

    // MARK: - Helpers

    /// Truncates a payload to a maximum byte size for logging.
    /// - Parameters:
    ///   - payload: String to truncate
    ///   - maxBytes: Maximum size in bytes
    /// - Returns: Truncated string or nil if input is nil
    private func truncatePayload(_ payload: String?, maxBytes: Int) -> String? {
        guard let payload else { return nil }
        guard payload.utf8.count > maxBytes else { return payload }

        let truncated = String(payload.prefix(maxBytes))
        return truncated + "... [truncated]"
    }

    /// Extracts the raw response body from an LLMError, if available.
    private func extractResponseBody(from error: Error) -> String? {
        guard let llmError = error as? LLMError else { return nil }
        switch llmError {
        case .apiError(_, _, let message):
            return truncatePayload(message, maxBytes: 10_000)
        case .rateLimited(let provider, let retryAfter):
            return "Rate limited by \(provider.rawValue), retry after \(retryAfter.map { "\(Int($0))s" } ?? "unknown")"
        case .tokenRefreshFailed(_, let detail):
            return truncatePayload(detail, maxBytes: 10_000)
        default:
            return nil
        }
    }
}

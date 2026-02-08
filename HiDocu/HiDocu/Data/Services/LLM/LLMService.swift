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

    private let keychainService: KeychainService
    private let accountRepository: any LLMAccountRepository
    private let apiLogRepository: any APILogRepository
    private let documentService: DocumentService
    private let settingsService: SettingsService

    // MARK: - Provider Registry

    private let providers: [LLMProvider: any LLMProviderStrategy]

    // MARK: - Model Cache

    /// Cached available models across all providers, sorted by provider then model name.
    private(set) var availableModels: [AvailableModel] = []

    /// Guard against concurrent refresh calls.
    private var isRefreshingModels = false

    // MARK: - Round-Robin State

    private var roundRobinCounters: [LLMProvider: Int] = [:]
    private var excludedAccounts: [Int64: Date] = [:]
    private let excludeDuration: TimeInterval = 60 // 60 seconds backoff

    // MARK: - Initialization

    init(
        keychainService: KeychainService,
        accountRepository: any LLMAccountRepository,
        apiLogRepository: any APILogRepository,
        documentService: DocumentService,
        settingsService: SettingsService,
        claudeProvider: any LLMProviderStrategy,
        codexProvider: any LLMProviderStrategy,
        geminiProvider: any LLMProviderStrategy,
        antigravityProvider: any LLMProviderStrategy
    ) {
        self.keychainService = keychainService
        self.accountRepository = accountRepository
        self.apiLogRepository = apiLogRepository
        self.documentService = documentService
        self.settingsService = settingsService

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

        // Find any active account for this provider
        let accounts = try await accountRepository.fetchActive(provider: provider)
        guard let account = accounts.first else {
            throw LLMError.noAccountsConfigured(provider)
        }

        // Get valid access token and token data (single keychain load)
        let (accessToken, tokenData) = try await getValidAccessToken(for: account)

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        // Fetch models from provider
        let models = try await strategy.fetchModels(accessToken: accessToken, accountId: tokenData.accountId)
        AppLogger.llm.info("Fetched \(models.count) models for \(provider.rawValue)")
        return models
    }

    /// Refreshes the cached list of available models from all providers.
    /// Silently skips providers with no configured accounts.
    /// Deduplicates concurrent calls — only one refresh runs at a time.
    func refreshAvailableModels() async {
        guard !isRefreshingModels else { return }
        isRefreshingModels = true
        defer { isRefreshingModels = false }
        AppLogger.llm.info("Refreshing available models cache")
        var allModels: [AvailableModel] = []
        for provider in LLMProvider.allCases {
            do {
                let models = try await fetchModels(provider: provider)
                allModels.append(contentsOf: models.map { AvailableModel(provider: provider, modelId: $0.id, displayName: $0.displayName) })
            } catch let error as LLMError {
                if case .noAccountsConfigured = error { }
                else { AppLogger.llm.warning("Failed to fetch models for \(provider.rawValue): \(error.localizedDescription)") }
            } catch {
                AppLogger.llm.warning("Failed to fetch models for \(provider.rawValue): \(error.localizedDescription)")
            }
        }
        availableModels = allModels.sorted {
            if $0.provider.rawValue != $1.provider.rawValue {
                return $0.provider.rawValue < $1.provider.rawValue
            }
            return $0.modelId < $1.modelId
        }
        let count = availableModels.count
        AppLogger.llm.info("Cached \(count) available models")
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
        let (accessToken, currentTokenData) = try await getValidAccessToken(for: account)

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
            // On rate limit, exclude account and rethrow
            if case .rateLimited = error {
                excludeAccount(account.id)
                throw error
            }
            // On 401, refresh token once and retry
            if case .apiError(_, let statusCode, _) = error, statusCode == 401 {
                AppLogger.llm.warning("Received 401, refreshing token and retrying")
                let (newAccessToken, refreshedTokenData) = try await refreshAndGetToken(for: account)
                response = try await strategy.chat(
                    messages: messages,
                    model: model,
                    accessToken: newAccessToken,
                    options: options,
                    tokenData: refreshedTokenData
                )
            } else {
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
    private static let maxInlineDataSize = 18 * 1024 * 1024 // 18 MB

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

        if totalSize > Self.maxInlineDataSize {
            let sizeMB = totalSize / (1024 * 1024)
            throw LLMError.invalidResponse(
                detail: "Audio files total \(sizeMB) MB, exceeding the 18 MB inline limit. Use shorter recordings."
            )
        }

        return attachments
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

        // Helper: single chat call with 401 retry and rate-limit exclusion
        let chatWithRetry: () async throws -> LLMResponse = {
            let (accessToken, tokenData) = try await self.getValidAccessToken(for: account)
            do {
                return try await strategy.chat(
                    messages: messages, model: model, accessToken: accessToken,
                    options: options, tokenData: tokenData
                )
            } catch let error as LLMError {
                if case .rateLimited = error {
                    self.excludeAccount(account.id)
                    throw error
                }
                if case .apiError(_, let statusCode, _) = error, statusCode == 401 {
                    AppLogger.llm.warning("Received 401 during transcription, refreshing token and retrying")
                    let (newToken, refreshedData) = try await self.refreshAndGetToken(for: account)
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
            responsePayload: nil,
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

    // MARK: - Token Management (Private)

    /// Gets a valid access token and token data for an account, refreshing if expired.
    /// - Parameter account: Account to get token for
    /// - Returns: Tuple of valid access token and token data
    /// - Throws: `LLMError` if token refresh fails
    private func getValidAccessToken(for account: LLMAccount) async throws -> (accessToken: String, tokenData: TokenData) {
        // Load token from keychain
        guard let tokenData = try keychainService.loadToken(identifier: account.keychainIdentifier) else {
            throw LLMError.authenticationFailed(
                provider: account.provider,
                detail: "No token found in keychain"
            )
        }

        guard let strategy = providers[account.provider] else {
            throw LLMError.authenticationFailed(
                provider: account.provider,
                detail: "Provider not supported"
            )
        }

        // Check if token is expired
        if strategy.isTokenExpired(tokenData.expiresAt) {
            AppLogger.llm.info("Token expired for account id=\(account.id), refreshing")
            return try await refreshAndGetToken(for: account)
        }

        return (tokenData.accessToken, tokenData)
    }

    /// Refreshes an account's access token and saves to keychain.
    /// - Parameter account: Account to refresh token for
    /// - Returns: Tuple of new access token and token data
    /// - Throws: `LLMError` if refresh fails
    private func refreshAndGetToken(for account: LLMAccount) async throws -> (accessToken: String, tokenData: TokenData) {
        // Load current token
        guard let currentToken = try keychainService.loadToken(identifier: account.keychainIdentifier) else {
            throw LLMError.tokenRefreshFailed(
                provider: account.provider,
                detail: "No token found in keychain"
            )
        }

        guard let strategy = providers[account.provider] else {
            throw LLMError.tokenRefreshFailed(
                provider: account.provider,
                detail: "Provider not supported"
            )
        }

        // Refresh token
        let newBundle = try await strategy.refreshToken(currentToken.refreshToken)

        // Save new token to keychain
        let newTokenData = TokenData(
            accessToken: newBundle.accessToken,
            refreshToken: newBundle.refreshToken,
            expiresAt: newBundle.expiresAt,
            idToken: newBundle.idToken,
            accountId: newBundle.accountId,
            projectId: newBundle.projectId,
            clientId: currentToken.clientId,
            clientSecret: newBundle.clientSecret
        )
        try keychainService.saveToken(newTokenData, identifier: account.keychainIdentifier)

        // Update lastUsedAt in database
        try await accountRepository.updateLastUsed(id: account.id)

        AppLogger.llm.info("Token refreshed for account id=\(account.id)")
        return (newBundle.accessToken, newTokenData)
    }

    // MARK: - Account Selection (Private)

    /// Selects an account for the provider using round-robin with exclusion.
    /// - Parameter provider: Provider to select account for
    /// - Returns: Selected account
    /// - Throws: `LLMError.noAccountsConfigured` if no accounts available
    private func selectAccount(provider: LLMProvider) async throws -> LLMAccount {
        // Get active accounts
        var accounts = try await accountRepository.fetchActive(provider: provider)

        // Filter out temporarily excluded accounts
        let now = Date()
        accounts = accounts.filter { account in
            if let excludedUntil = excludedAccounts[account.id] {
                return now > excludedUntil
            }
            return true
        }

        guard !accounts.isEmpty else {
            throw LLMError.noAccountsConfigured(provider)
        }

        // Round-robin selection
        let counter = roundRobinCounters[provider, default: 0]
        let selectedIndex = counter % accounts.count
        let selected = accounts[selectedIndex]

        // Increment counter
        roundRobinCounters[provider] = counter + 1

        AppLogger.llm.info("Selected account id=\(selected.id) for \(provider.rawValue) (round-robin: \(counter))")
        return selected
    }

    /// Temporarily excludes an account from selection (60s backoff).
    /// - Parameter accountId: Account ID to exclude
    private func excludeAccount(_ accountId: Int64) {
        excludedAccounts[accountId] = Date().addingTimeInterval(self.excludeDuration)
        AppLogger.llm.info("Excluded account id=\(accountId) for \(Int(self.excludeDuration))s")
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
}

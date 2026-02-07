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
        geminiProvider: any LLMProviderStrategy
    ) {
        self.keychainService = keychainService
        self.accountRepository = accountRepository
        self.apiLogRepository = apiLogRepository
        self.documentService = documentService
        self.settingsService = settingsService

        self.providers = [
            .claude: claudeProvider,
            .codex: codexProvider,
            .gemini: geminiProvider
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
    func fetchModels(provider: LLMProvider) async throws -> [String] {
        AppLogger.llm.info("Fetching models for \(provider.rawValue)")

        // Find any active account for this provider
        let accounts = try await accountRepository.fetchActive(provider: provider)
        guard let account = accounts.first else {
            throw LLMError.noAccountsConfigured(provider)
        }

        // Load token data (for access token + provider-specific metadata like accountId)
        guard let tokenData = try keychainService.loadToken(identifier: account.keychainIdentifier) else {
            throw LLMError.authenticationFailed(provider: provider, detail: "No token found in keychain")
        }

        // Get valid access token (may refresh if expired)
        let accessToken = try await getValidAccessToken(for: account)

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        // Fetch models from provider
        let models = try await strategy.fetchModels(accessToken: accessToken, accountId: tokenData.accountId)
        AppLogger.llm.info("Fetched \(models.count) models for \(provider.rawValue)")
        return models
    }

    // MARK: - Summary Generation

    /// Generates a summary for a document using configured LLM settings.
    /// - Parameter document: Document to summarize
    /// - Returns: LLM response with generated summary
    /// - Throws: `LLMError` if generation fails
    func generateSummary(for document: Document) async throws -> LLMResponse {
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

        // Get settings
        let settings = settingsService.settings.llm
        guard let providerRawValue = LLMProvider(rawValue: settings.defaultProvider) else {
            throw LLMError.authenticationFailed(
                provider: .claude,
                detail: "Invalid default provider: \(settings.defaultProvider)"
            )
        }
        let provider = providerRawValue
        let model = settings.defaultModel.isEmpty ? "claude-3-5-sonnet-20241022" : settings.defaultModel
        let promptTemplate = settings.summaryPromptTemplate

        // Build prompt — the template already contains {{body}} which gets replaced
        let systemPrompt = promptTemplate.replacingOccurrences(of: "{{body}}", with: body)

        // Select account
        let account = try await selectAccount(provider: provider)

        // Get valid access token
        let accessToken = try await getValidAccessToken(for: account)

        guard let strategy = providers[provider] else {
            throw LLMError.authenticationFailed(provider: provider, detail: "Provider not supported")
        }

        // Build messages — use instruction-only since body is embedded in the system prompt
        let messages = [
            LLMMessage(role: .user, content: "Please summarize this document according to the instructions.")
        ]

        let options = LLMRequestOptions(
            maxTokens: 4096,
            temperature: nil,
            systemPrompt: systemPrompt
        )

        // Make API call with retry on 401
        let response: LLMResponse
        do {
            response = try await strategy.chat(
                messages: messages,
                model: model,
                accessToken: accessToken,
                options: options
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
                let newAccessToken = try await refreshAndGetToken(for: account)
                response = try await strategy.chat(
                    messages: messages,
                    model: model,
                    accessToken: newAccessToken,
                    options: options
                )
            } else {
                throw error
            }
        }

        // Save summary to disk
        do {
            try await documentService.writeSummary(
                documentId: document.id,
                diskPath: document.diskPath,
                content: response.content
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
            requestPayload: truncatePayload(systemPrompt, maxBytes: 10_000),
            responsePayload: truncatePayload(response.content, maxBytes: 10_000),
            timestamp: Date(),
            documentId: document.id,
            sourceId: nil,
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

    // MARK: - Token Management (Private)

    /// Gets a valid access token for an account, refreshing if expired.
    /// - Parameter account: Account to get token for
    /// - Returns: Valid access token
    /// - Throws: `LLMError` if token refresh fails
    private func getValidAccessToken(for account: LLMAccount) async throws -> String {
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

        return tokenData.accessToken
    }

    /// Refreshes an account's access token and saves to keychain.
    /// - Parameter account: Account to refresh token for
    /// - Returns: New access token
    /// - Throws: `LLMError` if refresh fails
    private func refreshAndGetToken(for account: LLMAccount) async throws -> String {
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
        return newBundle.accessToken
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

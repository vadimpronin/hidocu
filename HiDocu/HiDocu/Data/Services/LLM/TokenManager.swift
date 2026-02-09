//
//  TokenManager.swift
//  HiDocu
//
//  Token lifecycle management for LLM accounts.
//  Handles token validation, refresh, and keychain persistence.
//

import Foundation

/// Actor responsible for managing LLM account tokens.
///
/// This actor provides thread-safe token validation and refresh operations,
/// isolated from the main actor. Token operations include:
/// - Loading tokens from keychain
/// - Validating expiration (5-minute buffer)
/// - Refreshing expired tokens via provider APIs
/// - Saving refreshed tokens to keychain
///
/// - Note: This is a plain `actor` (NOT `@MainActor`) to allow off-main-thread
///   execution. All operations are thread-safe and Sendable-compliant.
actor TokenManager {

    // MARK: - Dependencies

    private let keychainService: KeychainService
    private let accountRepository: any LLMAccountRepository
    private let providers: [LLMProvider: any LLMProviderStrategy]

    // MARK: - Initialization

    /// Initializes the token manager with required dependencies.
    /// - Parameters:
    ///   - keychainService: Keychain service for token persistence
    ///   - accountRepository: Repository for updating account metadata
    ///   - providers: Dictionary of provider strategies for token refresh
    init(
        keychainService: KeychainService,
        accountRepository: any LLMAccountRepository,
        providers: [LLMProvider: any LLMProviderStrategy]
    ) {
        self.keychainService = keychainService
        self.accountRepository = accountRepository
        self.providers = providers
    }

    // MARK: - Token Management

    /// Gets a valid access token for an account, refreshing if expired.
    ///
    /// This method:
    /// 1. Loads the token from keychain
    /// 2. Checks expiration (with 5-minute buffer)
    /// 3. Refreshes if expired or about to expire
    /// 4. Returns the valid access token and full token data
    ///
    /// - Parameter account: The account to get a token for
    /// - Returns: Tuple containing the access token and full token data
    /// - Throws: `LLMError.authenticationFailed` if token not found
    /// - Throws: Provider-specific errors if refresh fails
    func getValidAccessToken(for account: LLMAccount) async throws -> (accessToken: String, tokenData: TokenData) {
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

        // Check if token is expired (with 5-minute buffer)
        if strategy.isTokenExpired(tokenData.expiresAt) {
            AppLogger.llm.info("Token expired for account id=\(account.id), refreshing")
            return try await refreshAndGetToken(for: account)
        }

        return (tokenData.accessToken, tokenData)
    }

    /// Refreshes an account's access token and saves to keychain.
    ///
    /// This method:
    /// 1. Loads the current token (to get refresh token)
    /// 2. Calls the provider's refresh endpoint
    /// 3. Saves the new token to keychain
    /// 4. Updates the account's lastUsedAt timestamp
    /// 5. Returns the new access token and token data
    ///
    /// - Parameter account: The account to refresh
    /// - Returns: Tuple containing the new access token and token data
    /// - Throws: `LLMError.tokenRefreshFailed` if token not found or refresh fails
    func refreshAndGetToken(for account: LLMAccount) async throws -> (accessToken: String, tokenData: TokenData) {
        // Load current token to get refresh token
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

        // Call provider's refresh endpoint
        let newBundle = try await strategy.refreshToken(currentToken.refreshToken)

        // Build new token data, preserving clientId from current token
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

        // Save to keychain
        try keychainService.saveToken(newTokenData, identifier: account.keychainIdentifier)

        // Update lastUsedAt in database
        try await accountRepository.updateLastUsed(id: account.id)

        AppLogger.llm.info("Token refreshed for account id=\(account.id)")
        return (newBundle.accessToken, newTokenData)
    }
}

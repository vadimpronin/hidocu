//
//  LLMProviderStrategy.swift
//  HiDocu
//
//  Protocol defining provider-specific LLM authentication and API operations.
//

import Foundation

/// Strategy pattern for implementing provider-specific LLM operations.
/// Each provider (Claude, OpenAI, Gemini) implements this protocol.
protocol LLMProviderStrategy: Sendable {
    /// The provider this strategy implements.
    var provider: LLMProvider { get }

    /// Initiates OAuth authentication flow and returns token bundle.
    /// - Returns: Token bundle containing access/refresh tokens and user info
    /// - Throws: `LLMError` if authentication fails
    func authenticate() async throws -> OAuthTokenBundle

    /// Refreshes an expired access token using the refresh token.
    /// - Parameter refreshToken: Valid refresh token
    /// - Returns: New token bundle with refreshed credentials
    /// - Throws: `LLMError` if refresh fails
    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenBundle

    /// Checks if a token has expired based on its expiration date.
    /// - Parameter expiresAt: Token expiration timestamp
    /// - Returns: `true` if token is expired or expires within 5 minutes
    func isTokenExpired(_ expiresAt: Date) -> Bool

    /// Fetches available models for the authenticated account.
    /// - Parameters:
    ///   - accessToken: Valid access token
    ///   - accountId: Optional provider-specific account ID (e.g., chatgpt_account_id for Codex)
    /// - Returns: Array of model info pairs (id + display name)
    /// - Throws: `LLMError` if fetch fails
    func fetchModels(accessToken: String, accountId: String?) async throws -> [ModelInfo]

    /// Sends a chat completion request to the provider's API.
    /// - Parameters:
    ///   - messages: Conversation history
    ///   - model: Model identifier (e.g., "claude-3-opus-20240229")
    ///   - accessToken: Valid access token
    ///   - options: Request configuration (max tokens, temperature, etc.)
    ///   - tokenData: Optional token data with provider-specific metadata (e.g., projectId for Gemini)
    /// - Returns: Completed response with content and metadata
    /// - Throws: `LLMError` if request fails
    func chat(
        messages: [LLMMessage],
        model: String,
        accessToken: String,
        options: LLMRequestOptions,
        tokenData: TokenData?
    ) async throws -> LLMResponse
}

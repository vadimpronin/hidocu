import Foundation

/// Routes token refresh requests to the appropriate provider
enum TokenRefresher {

    /// Refresh tokens for the given provider
    static func refresh(
        provider: LLMProvider,
        refreshToken: String,
        httpClient: HTTPClient
    ) async throws -> LLMCredentials {
        switch provider {
        case .claudeCode:
            return try await ClaudeCodeAuthProvider.refreshToken(
                refreshToken: refreshToken,
                httpClient: httpClient
            )
        case .geminiCLI, .antigravity:
            return try await GoogleOAuthProvider.refreshToken(
                refreshToken: refreshToken,
                provider: provider,
                httpClient: httpClient
            )
        }
    }
}

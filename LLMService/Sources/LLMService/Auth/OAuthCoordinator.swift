import Foundation

/// Orchestrates the full OAuth login flow for all provider types
enum OAuthCoordinator {

    /// Perform the complete login flow for a provider
    static func login(
        session: LLMAccountSession,
        httpClient: HTTPClient,
        oauthLauncher: OAuthSessionLauncher,
        callbackScheme: String = "llmservice"
    ) async throws {
        let provider = session.info.provider
        let state = UUID().uuidString

        switch provider {
        case .claudeCode:
            try await loginClaude(
                session: session,
                state: state,
                callbackScheme: callbackScheme,
                httpClient: httpClient,
                oauthLauncher: oauthLauncher
            )

        case .geminiCLI:
            try await loginGoogle(
                session: session,
                provider: provider,
                state: state,
                callbackScheme: callbackScheme,
                httpClient: httpClient,
                oauthLauncher: oauthLauncher
            )

        case .antigravity:
            try await loginAntigravity(
                session: session,
                state: state,
                callbackScheme: callbackScheme,
                httpClient: httpClient,
                oauthLauncher: oauthLauncher
            )
        }
    }

    // MARK: - Provider-Specific Flows

    private static func loginClaude(
        session: LLMAccountSession,
        state: String,
        callbackScheme: String,
        httpClient: HTTPClient,
        oauthLauncher: OAuthSessionLauncher
    ) async throws {
        let pkceCodes = try PKCEGenerator.generate()
        let authURL = ClaudeCodeAuthProvider.buildAuthURL(
            pkceCodes: pkceCodes,
            state: state,
            callbackScheme: callbackScheme
        )

        let callbackURL = try await oauthLauncher.authenticate(url: authURL, callbackScheme: callbackScheme)
        let code = try extractCode(from: callbackURL)

        let (credentials, email) = try await ClaudeCodeAuthProvider.exchangeCodeForTokens(
            code: code,
            state: state,
            pkceCodes: pkceCodes,
            callbackScheme: callbackScheme,
            httpClient: httpClient
        )

        var info = session.info
        info.identifier = email
        info.displayName = email
        try await session.save(info: info, credentials: credentials)
    }

    private static func loginGoogle(
        session: LLMAccountSession,
        provider: LLMProvider,
        state: String,
        callbackScheme: String,
        httpClient: HTTPClient,
        oauthLauncher: OAuthSessionLauncher
    ) async throws {
        let authURL = GoogleOAuthProvider.buildAuthURL(
            provider: provider,
            state: state,
            callbackScheme: callbackScheme
        )

        let callbackURL = try await oauthLauncher.authenticate(url: authURL, callbackScheme: callbackScheme)
        let code = try extractCode(from: callbackURL)

        let (credentials, email) = try await GoogleOAuthProvider.exchangeCodeForTokens(
            code: code,
            provider: provider,
            callbackScheme: callbackScheme,
            httpClient: httpClient
        )

        var info = session.info
        info.identifier = email
        info.displayName = email
        try await session.save(info: info, credentials: credentials)
    }

    private static func loginAntigravity(
        session: LLMAccountSession,
        state: String,
        callbackScheme: String,
        httpClient: HTTPClient,
        oauthLauncher: OAuthSessionLauncher
    ) async throws {
        let authURL = GoogleOAuthProvider.buildAuthURL(
            provider: .antigravity,
            state: state,
            callbackScheme: callbackScheme
        )

        let callbackURL = try await oauthLauncher.authenticate(url: authURL, callbackScheme: callbackScheme)
        let code = try extractCode(from: callbackURL)

        let (credentials, email) = try await GoogleOAuthProvider.exchangeCodeForTokens(
            code: code,
            provider: .antigravity,
            callbackScheme: callbackScheme,
            httpClient: httpClient
        )

        // Antigravity additionally requires a project ID from loadCodeAssist
        guard let accessToken = credentials.accessToken else {
            throw LLMServiceError(
                traceId: "antigravity-login",
                message: "No access token after token exchange"
            )
        }
        let projectId = try await GoogleOAuthProvider.fetchProjectID(
            accessToken: accessToken,
            httpClient: httpClient
        )

        var info = session.info
        info.identifier = email
        info.displayName = email
        info.metadata["project_id"] = projectId
        try await session.save(info: info, credentials: credentials)
    }

    // MARK: - Helpers

    private static func extractCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw LLMServiceError(
                traceId: "oauth-callback",
                message: "No authorization code in callback URL"
            )
        }
        return code
    }
}

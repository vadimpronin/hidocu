import Foundation
import OSLog

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: "com.llmservice", category: "OAuthCoordinator")

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
        logger.info("login: provider=\(provider.rawValue), state=\(state)")

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
                httpClient: httpClient
            )

        case .antigravity:
            try await loginGoogle(
                session: session,
                provider: provider,
                state: state,
                httpClient: httpClient
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
        let code = try extractCode(from: callbackURL, expectedState: state)

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
        httpClient: HTTPClient
    ) async throws {
        let redirectURI = GoogleOAuthProvider.redirectURI(for: provider)
        logger.info("loginGoogle: redirectURI=\(redirectURI)")

        let authURL = GoogleOAuthProvider.buildAuthURL(
            provider: provider,
            state: state,
            redirectURI: redirectURI
        )
        logger.info("loginGoogle: authURL built, creating LocalOAuthServer on port \(GoogleOAuthProvider.callbackPort(for: provider))")

        let server = LocalOAuthServer(
            port: GoogleOAuthProvider.callbackPort(for: provider),
            callbackPath: GoogleOAuthProvider.callbackPath(for: provider)
        )

        logger.info("loginGoogle: calling server.awaitCallback() with onListenerReady browser open")
        let callbackURL = try await server.awaitCallback {
            logger.info("loginGoogle: onListenerReady fired — opening browser now")
            Self.openInBrowser(url: authURL)
        }
        logger.info("loginGoogle: got callbackURL: \(callbackURL.absoluteString)")

        let code = try extractCode(from: callbackURL, expectedState: state)
        logger.info("loginGoogle: extracted code, exchanging for tokens")

        let (credentials, email) = try await GoogleOAuthProvider.exchangeCodeForTokens(
            code: code,
            provider: provider,
            redirectURI: redirectURI,
            httpClient: httpClient
        )
        logger.info("loginGoogle: token exchange complete, email=\(email ?? "nil")")

        var info = session.info
        info.identifier = email
        info.displayName = email

        // Both GeminiCLI and Antigravity require a project ID from loadCodeAssist
        logger.info("loginGoogle: fetching project ID via loadCodeAssist")
        let projectId = try await GoogleOAuthProvider.fetchProjectID(
            accessToken: credentials.accessToken ?? "",
            provider: provider,
            httpClient: httpClient
        )
        info.metadata["project_id"] = projectId
        logger.info("loginGoogle: project_id=\(projectId)")

        try await session.save(info: info, credentials: credentials)
        logger.info("loginGoogle: saved credentials successfully")
    }

    // MARK: - Helpers

    private static func extractCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            logger.error("extractCode: invalid callback URL: \(url.absoluteString)")
            throw LLMServiceError(
                traceId: "oauth-callback",
                message: "Invalid callback URL"
            )
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            logger.error("extractCode: no code in URL: \(url.absoluteString)")
            throw LLMServiceError(
                traceId: "oauth-callback",
                message: "No authorization code in callback URL"
            )
        }

        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        logger.info("extractCode: returnedState=\(returnedState ?? "nil"), expectedState=\(expectedState)")
        guard returnedState == expectedState else {
            logger.error("extractCode: STATE MISMATCH — returned=\(returnedState ?? "nil") expected=\(expectedState)")
            throw LLMServiceError(
                traceId: "oauth-callback",
                message: "OAuth state mismatch — possible CSRF attack"
            )
        }

        return code
    }

    private static func openInBrowser(url: URL) {
        logger.info("openInBrowser: dispatching to MainActor")
        Task { @MainActor in
            logger.info("openInBrowser: on MainActor, opening URL")
            #if canImport(AppKit) && !targetEnvironment(macCatalyst)
            NSWorkspace.shared.open(url)
            #elseif canImport(UIKit)
            UIApplication.shared.open(url)
            #endif
        }
    }
}

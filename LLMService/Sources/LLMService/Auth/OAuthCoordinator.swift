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
            try await loginGemini(
                session: session,
                state: state,
                httpClient: httpClient
            )

        case .antigravity:
            try await loginAntigravity(
                session: session,
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

    private static func loginGemini(
        session: LLMAccountSession,
        state: String,
        httpClient: HTTPClient
    ) async throws {
        let redirectURI = GeminiAuthProvider.redirectURI
        logger.info("loginGemini: redirectURI=\(redirectURI)")

        let authURL = GeminiAuthProvider.buildAuthURL(
            state: state,
            redirectURI: redirectURI
        )
        logger.info("loginGemini: authURL built, creating LocalOAuthServer on port \(GeminiAuthProvider.callbackPort)")

        let server = LocalOAuthServer(
            port: GeminiAuthProvider.callbackPort,
            callbackPath: GeminiAuthProvider.callbackPath
        )

        logger.info("loginGemini: calling server.awaitCallback() with onListenerReady browser open")
        let callbackURL = try await server.awaitCallback {
            logger.info("loginGemini: onListenerReady fired — opening browser now")
            Self.openInBrowser(url: authURL)
        }
        logger.info("loginGemini: got callbackURL: \(callbackURL.absoluteString)")

        let code = try extractCode(from: callbackURL, expectedState: state)
        logger.info("loginGemini: extracted code, exchanging for tokens")

        let (credentials, email) = try await GeminiAuthProvider.exchangeCodeForTokens(
            code: code,
            redirectURI: redirectURI,
            httpClient: httpClient
        )
        logger.info("loginGemini: token exchange complete, email=\(email ?? "nil")")

        var info = session.info
        info.identifier = email
        info.displayName = email

        logger.info("loginGemini: fetching project ID via loadCodeAssist")
        let projectId = try await GeminiAuthProvider.fetchProjectID(
            accessToken: credentials.accessToken ?? "",
            httpClient: httpClient
        )
        info.metadata["project_id"] = projectId
        logger.info("loginGemini: project_id=\(projectId)")

        try await session.save(info: info, credentials: credentials)
        logger.info("loginGemini: saved credentials successfully")
    }

    private static func loginAntigravity(
        session: LLMAccountSession,
        state: String,
        httpClient: HTTPClient
    ) async throws {
        let redirectURI = AntigravityAuthProvider.redirectURI
        logger.info("loginAntigravity: redirectURI=\(redirectURI)")

        let authURL = AntigravityAuthProvider.buildAuthURL(
            state: state,
            redirectURI: redirectURI
        )
        logger.info("loginAntigravity: authURL built, creating LocalOAuthServer on port \(AntigravityAuthProvider.callbackPort)")

        let server = LocalOAuthServer(
            port: AntigravityAuthProvider.callbackPort,
            callbackPath: AntigravityAuthProvider.callbackPath
        )

        logger.info("loginAntigravity: calling server.awaitCallback() with onListenerReady browser open")
        let callbackURL = try await server.awaitCallback {
            logger.info("loginAntigravity: onListenerReady fired — opening browser now")
            Self.openInBrowser(url: authURL)
        }
        logger.info("loginAntigravity: got callbackURL: \(callbackURL.absoluteString)")

        let code = try extractCode(from: callbackURL, expectedState: state)
        logger.info("loginAntigravity: extracted code, exchanging for tokens")

        let (credentials, email) = try await AntigravityAuthProvider.exchangeCodeForTokens(
            code: code,
            redirectURI: redirectURI,
            httpClient: httpClient
        )
        logger.info("loginAntigravity: token exchange complete, email=\(email ?? "nil")")

        var info = session.info
        info.identifier = email
        info.displayName = email

        logger.info("loginAntigravity: fetching project ID via loadCodeAssist")
        let projectId = try await AntigravityAuthProvider.fetchProjectID(
            accessToken: credentials.accessToken ?? "",
            httpClient: httpClient
        )
        info.metadata["project_id"] = projectId
        logger.info("loginAntigravity: project_id=\(projectId)")

        try await session.save(info: info, credentials: credentials)
        logger.info("loginAntigravity: saved credentials successfully")
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

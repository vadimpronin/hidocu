//
//  ClaudeProvider.swift
//  HiDocu
//
//  Anthropic Claude provider implementation with OAuth2 + PKCE authentication.
//  Ported from CLIProxyAPI/internal/auth/claude and CLIProxyAPI/internal/runtime/executor/claude_executor.go
//

import Foundation
import Security
import os

/// Anthropic Claude provider implementation.
final class ClaudeProvider: LLMProviderStrategy, Sendable {
    // MARK: - OAuth Constants

    private static let authURL = "https://claude.ai/oauth/authorize"
    private static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let redirectURI = "http://localhost:54545/callback"
    private static let scopes = "org:create_api_key user:profile user:inference"
    private static let callbackPort: UInt16 = 54545
    private static let callbackPath = "/callback"

    // MARK: - API Constants

    private static let apiBaseURL = "https://api.anthropic.com"
    private static let apiVersion = "2023-06-01"
    private static let betaHeader = "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14,prompt-caching-2024-07-31"
    private static let userAgent = "claude-cli/1.0.83 (external, cli)"

    // MARK: - Properties

    let provider: LLMProvider = .claude
    private let urlSession: URLSession

    // MARK: - Initialization

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - LLMProviderStrategy

    func authenticate() async throws -> OAuthTokenBundle {
        AppLogger.llm.info("Starting Claude OAuth authentication")

        // Generate PKCE codes and state
        let pkceCodes = try PKCEHelper.generatePKCECodes()
        let state = try PKCEHelper.generateState()

        // Build authorization URL
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: pkceCodes.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw LLMError.authenticationFailed(provider: .claude, detail: "Failed to construct authorization URL")
        }

        AppLogger.llm.debug("Authorization URL constructed: \(authURL.absoluteString)")

        // Create callback server and await authorization
        let server = OAuthCallbackServer(port: Self.callbackPort, callbackPath: Self.callbackPath, provider: .claude)
        let result = try await server.awaitCallback(authorizationURL: authURL)

        AppLogger.llm.info("OAuth callback received with code")

        // Exchange authorization code for tokens
        return try await exchangeCodeForTokens(
            code: result.code,
            state: result.state.isEmpty ? state : result.state,
            pkceCodes: pkceCodes
        )
    }

    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenBundle {
        AppLogger.llm.info("Refreshing Claude access token")

        guard !refreshToken.isEmpty else {
            throw LLMError.tokenRefreshFailed(provider: .claude, detail: "Refresh token is empty")
        }

        let requestBody: [String: Any] = [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Response is not HTTP")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Token refresh failed with status \(httpResponse.statusCode): \(message)")
            throw LLMError.tokenRefreshFailed(provider: .claude, detail: "HTTP \(httpResponse.statusCode): \(message)")
        }

        return try parseTokenResponse(data)
    }

    func isTokenExpired(_ expiresAt: Date) -> Bool {
        // Consider expired if within 5 minutes of expiration
        expiresAt.timeIntervalSinceNow < 300
    }

    func fetchModels(accessToken: String, accountId: String?) async throws -> [String] {
        // Claude OAuth tokens have a fixed set of models
        AppLogger.llm.debug("Returning hardcoded Claude model list")
        return [
            "claude-sonnet-4-5-20250929",
            "claude-opus-4-6",
            "claude-haiku-4-5-20251001"
        ]
    }

    func chat(
        messages: [LLMMessage],
        model: String,
        accessToken: String,
        options: LLMRequestOptions,
        tokenData: TokenData? = nil
    ) async throws -> LLMResponse {
        AppLogger.llm.info("Sending chat request to Claude API with model: \(model)")

        // Separate system messages from conversation messages
        var systemMessages: [[String: Any]] = [
            [
                "type": "text",
                "text": "x-anthropic-billing-header: cc_version=2.1.37.3a3; cc_entrypoint=cli"
            ],
            [
                "type": "text",
                "text": "\nYou "
            ]
        ]

        var conversationMessages: [[String: Any]] = [
            [
                "role": "user",
                "content": "<system-reminder>\nAs </system-reminder>\n"
            ]
        ]

        for message in messages {
            if message.role == .system {
                systemMessages += [
                    [
                        "type": "text",
                        "text": message.content
                    ]
                ]
            } else {
                conversationMessages.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }
        }

        // Build request body — matches Go reference (ConvertOpenAIRequestToClaude + applyCloaking)
        var requestBody: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens ?? 32000,
            "messages": conversationMessages,
            "metadata": [
                "user_id": generateFakeUserID()
            ]
        ]

        // Add system prompt (prioritize options.systemPrompt, then collected system messages)
        if let systemPrompt = options.systemPrompt {
            requestBody["system"] = systemPrompt
        } else if !systemMessages.isEmpty {
            requestBody["system"] = systemMessages
        }

        // Add temperature if specified
        if let temperature = options.temperature {
            requestBody["temperature"] = temperature
        }

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        // Build request — headers match Go reference (applyClaudeHeaders)
        var request = URLRequest(url: URL(string: "\(Self.apiBaseURL)/v1/messages?beta=true")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Anthropic-Version")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "Anthropic-Beta")
        request.setValue("true", forHTTPHeaderField: "Anthropic-Dangerous-Direct-Browser-Access")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("cli", forHTTPHeaderField: "X-App")
        request.setValue("stream", forHTTPHeaderField: "X-Stainless-Helper-Method")
        request.setValue("0", forHTTPHeaderField: "X-Stainless-Retry-Count")
        request.setValue("v24.3.0", forHTTPHeaderField: "X-Stainless-Runtime-Version")
        request.setValue("0.55.1", forHTTPHeaderField: "X-Stainless-Package-Version")
        request.setValue("node", forHTTPHeaderField: "X-Stainless-Runtime")
        request.setValue("js", forHTTPHeaderField: "X-Stainless-Lang")
        request.setValue("arm64", forHTTPHeaderField: "X-Stainless-Arch")
        request.setValue("MacOS", forHTTPHeaderField: "X-Stainless-Os")
        request.setValue("60", forHTTPHeaderField: "X-Stainless-Timeout")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.httpBody = jsonData

        AppLogger.llm.debug("Sending request to \(request.url?.absoluteString ?? "unknown")")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Response is not HTTP")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Chat request failed with status \(httpResponse.statusCode): \(message)")
            throw LLMError.apiError(provider: .claude, statusCode: httpResponse.statusCode, message: message)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Response is not valid JSON")
        }

        // Extract content from response
        guard let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.invalidResponse(detail: "No text content in response")
        }

        // Extract usage information
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int
        let outputTokens = usage?["output_tokens"] as? Int
        let finishReason = json["stop_reason"] as? String

        AppLogger.llm.info("Chat response received: \(outputTokens ?? 0) output tokens")

        return LLMResponse(
            content: text,
            model: model,
            provider: .claude,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            finishReason: finishReason
        )
    }

    // MARK: - Private Helpers

    /// Generates a fake user ID for request metadata.
    /// Format: user_{64-hex-chars}_account__session_{UUID-v4}
    private func generateFakeUserID() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hexPart = bytes.map { String(format: "%02x", $0) }.joined()
        let uuidPart = UUID().uuidString.lowercased()
        return "user_\(hexPart)_account__session_\(uuidPart)"
    }

    /// Exchanges authorization code for access and refresh tokens.
    private func exchangeCodeForTokens(
        code: String,
        state: String,
        pkceCodes: PKCECodes
    ) async throws -> OAuthTokenBundle {
        AppLogger.llm.debug("Exchanging authorization code for tokens")

        // Parse code#state format if present
        var actualCode = code
        var actualState = state

        if code.contains("#") {
            let parts = code.split(separator: "#", maxSplits: 1)
            actualCode = String(parts[0])
            if parts.count > 1 {
                actualState = String(parts[1])
            }
        }

        var requestBody: [String: Any] = [
            "code": actualCode,
            "state": actualState,
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "code_verifier": pkceCodes.codeVerifier
        ]

        // Include state if non-empty
        if !actualState.isEmpty {
            requestBody["state"] = actualState
        }

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Response is not HTTP")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Token exchange failed with status \(httpResponse.statusCode): \(message)")
            throw LLMError.authenticationFailed(provider: .claude, detail: "HTTP \(httpResponse.statusCode): \(message)")
        }

        return try parseTokenResponse(data)
    }

    /// Parses token response JSON into OAuthTokenBundle.
    private func parseTokenResponse(_ data: Data) throws -> OAuthTokenBundle {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Response is not valid JSON")
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw LLMError.invalidResponse(detail: "Missing required token fields")
        }

        // Extract email from account.email_address
        var email = ""
        if let account = json["account"] as? [String: Any],
           let emailAddress = account["email_address"] as? String {
            email = emailAddress
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        AppLogger.llm.info("Token response parsed successfully for email: \(email)")

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            email: email
        )
    }
}

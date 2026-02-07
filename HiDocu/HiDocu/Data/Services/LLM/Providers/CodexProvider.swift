//
//  CodexProvider.swift
//  HiDocu
//
//  OpenAI Codex provider implementation with OAuth2 + PKCE authentication.
//  Ported from CLIProxyAPI/internal/auth/codex and CLIProxyAPI/internal/runtime/executor/codex_executor.go
//

import Foundation
import os

private let logger = Logger(subsystem: "com.hidocu.app", category: "llm")

/// OpenAI Codex provider implementation using the Responses API.
final class CodexProvider: LLMProviderStrategy, Sendable {
    // MARK: - OAuth Constants

    private static let authURL = "https://auth.openai.com/oauth/authorize"
    private static let tokenURL = "https://auth.openai.com/oauth/token"
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let redirectURI = "http://localhost:1455/auth/callback"
    private static let scopes = "openid email profile offline_access"
    private static let callbackPort: UInt16 = 1455
    private static let callbackPath = "/auth/callback"

    // MARK: - API Constants

    private static let apiBaseURL = "https://chatgpt.com/backend-api/codex"
    private static let userAgent = "codex_cli_rs/0.98.0 (Mac OS 26.0.1; arm64) Apple_Terminal/464"
    private static let clientVersion = "0.98.0"

    // MARK: - Properties

    let provider: LLMProvider = .codex
    private let urlSession: URLSession

    // MARK: - Initialization

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - LLMProviderStrategy

    func authenticate() async throws -> OAuthTokenBundle {
        logger.info("Starting Codex OAuth authentication")

        // Generate PKCE codes and state
        let pkceCodes = try PKCEHelper.generatePKCECodes()
        let state = try PKCEHelper.generateState()

        // Build authorization URL
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkceCodes.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "login"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true")
        ]

        guard let authURL = components.url else {
            throw LLMError.authenticationFailed(provider: .codex, detail: "Failed to construct authorization URL")
        }

        logger.debug("Authorization URL constructed: \(authURL.absoluteString)")

        // Create callback server and await authorization
        let server = OAuthCallbackServer(port: Self.callbackPort, callbackPath: Self.callbackPath, provider: .codex)
        let result = try await server.awaitCallback(authorizationURL: authURL)

        logger.info("OAuth callback received with code")

        // Exchange authorization code for tokens
        return try await exchangeCodeForTokens(code: result.code, pkceCodes: pkceCodes)
    }

    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenBundle {
        logger.info("Refreshing Codex access token")

        guard !refreshToken.isEmpty else {
            throw LLMError.tokenRefreshFailed(provider: .codex, detail: "Refresh token is empty")
        }

        // Build form-urlencoded body
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "scope", value: "openid profile email")
        ]

        guard let bodyString = components.percentEncodedQuery,
              let bodyData = bodyString.data(using: .utf8) else {
            throw LLMError.tokenRefreshFailed(provider: .codex, detail: "Failed to encode request body")
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Response is not HTTP")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Token refresh failed with status \(httpResponse.statusCode): \(message)")
            throw LLMError.tokenRefreshFailed(provider: .codex, detail: "HTTP \(httpResponse.statusCode): \(message)")
        }

        return try parseTokenResponse(data)
    }

    func isTokenExpired(_ expiresAt: Date) -> Bool {
        // Consider expired if within 5 minutes of expiration
        expiresAt.timeIntervalSinceNow < 300
    }

    func fetchModels(accessToken: String) async throws -> [String] {
        // Codex API models (hardcoded as per Go implementation)
        logger.debug("Returning hardcoded Codex model list")
        return [
            "gpt-4.1",
            "o3",
            "o4-mini",
            "gpt-4o"
        ]
    }

    func chat(
        messages: [LLMMessage],
        model: String,
        accessToken: String,
        options: LLMRequestOptions
    ) async throws -> LLMResponse {
        logger.info("Sending chat request to Codex API with model: \(model)")

        // Build Responses API format
        let requestBody = try buildResponsesAPIRequest(
            messages: messages,
            model: model,
            options: options
        )

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        // Build request
        var request = URLRequest(url: URL(string: "\(Self.apiBaseURL)/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.clientVersion, forHTTPHeaderField: "Version")
        request.setValue("responses=experimental", forHTTPHeaderField: "Openai-Beta")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "Originator")
        request.httpBody = jsonData

        logger.debug("Sending SSE request to \(request.url?.absoluteString ?? "unknown")")

        // Stream SSE events
        let eventStream = SSEParser.streamBytes(from: urlSession, request: request)

        var accumulatedText = ""
        var inputTokens: Int?
        var outputTokens: Int?
        var finishReason: String?

        do {
            for try await event in eventStream {
                guard let eventData = event.data.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                      let eventType = json["type"] as? String else {
                    continue
                }

                switch eventType {
                case "response.output_text.delta":
                    // Accumulate delta text
                    if let delta = json["delta"] as? String {
                        accumulatedText += delta
                    }

                case "response.completed":
                    // Extract final content and usage
                    if let response = json["response"] as? [String: Any] {
                        // Extract text from output array
                        if let output = response["output"] as? [[String: Any]] {
                            var fullText = ""
                            for item in output {
                                if let content = item["content"] as? [[String: Any]] {
                                    for contentItem in content {
                                        if let text = contentItem["text"] as? String {
                                            fullText += text
                                        }
                                    }
                                }
                            }
                            if !fullText.isEmpty {
                                accumulatedText = fullText
                            }
                        }

                        // Extract usage
                        if let usage = response["usage"] as? [String: Any] {
                            inputTokens = usage["input_tokens"] as? Int
                            outputTokens = usage["output_tokens"] as? Int
                        }
                    }
                    finishReason = "complete"

                default:
                    break
                }
            }
        } catch {
            logger.error("SSE stream error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard !accumulatedText.isEmpty else {
            throw LLMError.invalidResponse(detail: "No content received from stream")
        }

        logger.info("Chat response received: \(outputTokens ?? 0) output tokens")

        return LLMResponse(
            content: accumulatedText,
            model: model,
            provider: .codex,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            finishReason: finishReason
        )
    }

    // MARK: - Private Helpers

    /// Exchanges authorization code for access and refresh tokens.
    private func exchangeCodeForTokens(
        code: String,
        pkceCodes: PKCECodes
    ) async throws -> OAuthTokenBundle {
        logger.debug("Exchanging authorization code for tokens")

        // Build form-urlencoded body
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_verifier", value: pkceCodes.codeVerifier)
        ]

        guard let bodyString = components.percentEncodedQuery,
              let bodyData = bodyString.data(using: .utf8) else {
            throw LLMError.authenticationFailed(provider: .codex, detail: "Failed to encode request body")
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Response is not HTTP")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Token exchange failed with status \(httpResponse.statusCode): \(message)")
            throw LLMError.authenticationFailed(provider: .codex, detail: "HTTP \(httpResponse.statusCode): \(message)")
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
              let idToken = json["id_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw LLMError.invalidResponse(detail: "Missing required token fields")
        }

        // Parse JWT to extract email and account ID
        let (email, accountId) = parseJWT(idToken)

        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        logger.info("Token response parsed successfully for email: \(email)")

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            email: email,
            idToken: idToken,
            accountId: accountId
        )
    }

    /// Parses a JWT token to extract email and account ID.
    /// Minimal parsing without signature verification (server has already validated).
    private func parseJWT(_ token: String) -> (email: String, accountId: String?) {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            logger.warning("Invalid JWT format: expected 3 parts, got \(parts.count)")
            return ("", nil)
        }

        // Decode payload (second part)
        guard let payloadData = base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            logger.warning("Failed to decode JWT payload")
            return ("", nil)
        }

        let email = json["email"] as? String ?? ""

        // Extract ChatGPT account ID from custom claim
        var accountId: String?
        if let authInfo = json["https://api.openai.com/auth"] as? [String: Any] {
            accountId = authInfo["chatgpt_account_id"] as? String
        }

        return (email, accountId)
    }

    /// Decodes a Base64 URL-encoded string (RFC 4648 Section 5).
    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if necessary
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }

    /// Builds a Responses API request body from messages and options.
    private func buildResponsesAPIRequest(
        messages: [LLMMessage],
        model: String,
        options: LLMRequestOptions
    ) throws -> [String: Any] {
        // Extract system instructions
        var systemInstructions = ""
        if let systemPrompt = options.systemPrompt {
            systemInstructions = systemPrompt
        } else {
            let systemMessages = messages.filter { $0.role == .system }
            if !systemMessages.isEmpty {
                systemInstructions = systemMessages.map { $0.content }.joined(separator: "\n\n")
            }
        }

        // Convert conversation messages to Responses API input format
        var input: [[String: Any]] = []
        for message in messages where message.role != .system {
            let textType: String
            switch message.role {
            case .user:
                textType = "input_text"
            case .assistant:
                textType = "output_text"
            case .system:
                continue
            }

            input.append([
                "type": "message",
                "role": message.role.rawValue,
                "content": [
                    [
                        "type": textType,
                        "text": message.content
                    ]
                ]
            ])
        }

        var requestBody: [String: Any] = [
            "model": model,
            "stream": true,
            "instructions": systemInstructions,
            "input": input,
            "max_output_tokens": options.maxTokens
        ]

        // Add temperature if specified
        if let temperature = options.temperature {
            requestBody["temperature"] = temperature
        }

        return requestBody
    }
}

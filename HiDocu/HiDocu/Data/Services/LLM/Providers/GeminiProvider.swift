//
//  GeminiProvider.swift
//  HiDocu
//
//  Google Gemini LLM provider implementation using OAuth2 authentication.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.hidocu.app", category: "llm")

/// Google Gemini LLM provider strategy.
///
/// Implements OAuth2 authentication flow with client secret (not PKCE).
/// Uses standard Google OAuth endpoints and the Generative Language API.
///
/// Key differences from PKCE-based providers:
/// - Uses client_secret instead of PKCE code_verifier
/// - Client secret must be stored in OAuthTokenBundle for refresh operations
/// - Fetches user email from Google userinfo API after token exchange
final class GeminiProvider: LLMProviderStrategy, Sendable {
    // MARK: - OAuth Configuration

    // Note: Client secret is from the public Google CLI OAuth client (same as Gemini CLI).
    // This is standard practice for installed/native app OAuth flows where the secret
    // cannot be kept confidential (see Google OAuth docs for "installed applications").
    private static let clientID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
    private static let clientSecret = "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"
    private static let authURL = "https://accounts.google.com/o/oauth2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let redirectURI = "http://localhost:8085/oauth2callback"
    private static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ]
    private static let callbackPort: UInt16 = 8085
    private static let callbackPath = "/oauth2callback"

    // MARK: - API Configuration

    private static let apiBaseURL = "https://generativelanguage.googleapis.com/v1beta"
    private static let userinfoURL = "https://www.googleapis.com/oauth2/v1/userinfo?alt=json"

    // MARK: - Properties

    let provider: LLMProvider = .gemini
    private let urlSession: URLSession

    // MARK: - Initialization

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Initiates OAuth2 authentication flow without PKCE.
    ///
    /// Steps:
    /// 1. Generate random state for CSRF protection
    /// 2. Build authorization URL with client_id, scopes, and state
    /// 3. Start local callback server on port 8085
    /// 4. Open browser to authorization URL
    /// 5. Exchange authorization code for tokens using client_secret
    /// 6. Fetch user email from Google userinfo API
    ///
    /// - Returns: Token bundle with access/refresh tokens and user email
    /// - Throws: `LLMError` if authentication fails
    func authenticate() async throws -> OAuthTokenBundle {
        logger.info("Starting Gemini OAuth authentication flow")

        // Generate state
        let state = try PKCEHelper.generateState()

        // Build authorization URL
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw LLMError.authenticationFailed(provider: .gemini, detail: "Failed to construct authorization URL")
        }

        // Start callback server and await authorization code
        let server = OAuthCallbackServer(port: Self.callbackPort, callbackPath: Self.callbackPath, provider: .gemini)
        let result: OAuthResult

        do {
            result = try await server.awaitCallback(authorizationURL: authURL)
        } catch {
            logger.error("OAuth callback failed: \(error.localizedDescription)")
            throw LLMError.authenticationFailed(provider: .gemini, detail: error.localizedDescription)
        }

        // Verify state matches
        guard result.state == state else {
            throw LLMError.authenticationFailed(provider: .gemini, detail: "State parameter mismatch (CSRF protection)")
        }

        logger.debug("Received authorization code, exchanging for tokens")

        // Exchange code for tokens
        let tokenBundle = try await exchangeCodeForTokens(code: result.code)

        logger.info("Gemini authentication successful for user: \(tokenBundle.email)")
        return tokenBundle
    }

    /// Refreshes an expired access token using the refresh token.
    ///
    /// Note: Google may not return a new refresh_token in the response.
    /// If not present, we reuse the existing refresh token.
    ///
    /// - Parameter refreshToken: Valid refresh token
    /// - Returns: New token bundle with refreshed access token
    /// - Throws: `LLMError.tokenRefreshFailed` if refresh fails
    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenBundle {
        logger.info("Refreshing Gemini access token")

        // Build form body
        let bodyParams = [
            "client_id": Self.clientID,
            "client_secret": Self.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]

        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")

        guard let bodyData = bodyString.data(using: .utf8) else {
            throw LLMError.tokenRefreshFailed(provider: .gemini, detail: "Failed to encode request body")
        }

        // Create request
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        // Execute request
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            logger.error("Token refresh network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Token refresh failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw LLMError.tokenRefreshFailed(provider: .gemini, detail: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse response
        let json: [String: Any]

        do {
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to parse JSON response")
        }

        guard let accessToken = json["access_token"] as? String else {
            throw LLMError.invalidResponse(detail: "Missing access_token in response")
        }

        guard let expiresIn = json["expires_in"] as? Int else {
            throw LLMError.invalidResponse(detail: "Missing expires_in in response")
        }

        // Google may not return a new refresh token on refresh
        let newRefreshToken = (json["refresh_token"] as? String) ?? refreshToken

        let expiresAt = Date(timeIntervalSinceNow: TimeInterval(expiresIn))

        logger.debug("Token refresh successful, expires at: \(expiresAt)")

        // Fetch user email (we need it for the token bundle)
        let email = try await fetchUserEmail(accessToken: accessToken)

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAt,
            email: email,
            clientSecret: Self.clientSecret
        )
    }

    /// Checks if a token has expired with 5-minute safety margin.
    ///
    /// - Parameter expiresAt: Token expiration timestamp
    /// - Returns: `true` if token is expired or expires within 5 minutes
    func isTokenExpired(_ expiresAt: Date) -> Bool {
        expiresAt.timeIntervalSinceNow < 300
    }

    /// Returns hardcoded list of supported Gemini models.
    ///
    /// - Parameter accessToken: Valid access token (unused, kept for protocol conformance)
    /// - Returns: Array of model identifiers
    func fetchModels(accessToken: String) async throws -> [String] {
        [
            "gemini-2.5-flash",
            "gemini-2.5-pro",
            "gemini-2.0-flash"
        ]
    }

    /// Sends a chat completion request to the Gemini API.
    ///
    /// Converts messages to Gemini's format:
    /// - `system` messages → `systemInstruction` field
    /// - `user` messages → role `"user"`
    /// - `assistant` messages → role `"model"`
    ///
    /// - Parameters:
    ///   - messages: Conversation history
    ///   - model: Model identifier (e.g., "gemini-2.5-flash")
    ///   - accessToken: Valid access token
    ///   - options: Request configuration (max tokens, temperature, system prompt)
    /// - Returns: Completed response with content and token usage
    /// - Throws: `LLMError` if request fails
    func chat(
        messages: [LLMMessage],
        model: String,
        accessToken: String,
        options: LLMRequestOptions
    ) async throws -> LLMResponse {
        logger.info("Sending chat request to Gemini model: \(model)")

        // Build request URL
        let url = URL(string: "\(Self.apiBaseURL)/models/\(model):generateContent")!

        // Convert messages to Gemini format
        var contents: [[String: Any]] = []
        var systemInstructions: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                systemInstructions.append(message.content)
            case .user:
                contents.append([
                    "role": "user",
                    "parts": [["text": message.content]]
                ])
            case .assistant:
                contents.append([
                    "role": "model",
                    "parts": [["text": message.content]]
                ])
            }
        }

        // Build request body
        var requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": options.maxTokens
            ]
        ]

        // Add system instruction (prefer options.systemPrompt over message-based system prompts)
        let finalSystemPrompt = options.systemPrompt ?? systemInstructions.joined(separator: "\n\n")
        if !finalSystemPrompt.isEmpty {
            requestBody["systemInstruction"] = [
                "parts": [["text": finalSystemPrompt]]
            ]
        }

        // Serialize to JSON
        let bodyData: Data

        do {
            bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to serialize request body: \(error.localizedDescription)")
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        // Execute request
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            logger.error("Chat request network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        // Handle non-2xx status codes
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Chat request failed with status \(httpResponse.statusCode): \(errorMessage)")

            // Handle rate limiting
            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0) }
                throw LLMError.rateLimited(provider: .gemini, retryAfter: retryAfter)
            }

            throw LLMError.apiError(provider: .gemini, statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let json: [String: Any]

        do {
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to parse JSON response")
        }

        // Extract content from response
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            logger.error("Invalid response structure: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw LLMError.invalidResponse(detail: "Missing or invalid content in response")
        }

        // Extract usage metadata (optional)
        let usageMetadata = json["usageMetadata"] as? [String: Any]
        let inputTokens = usageMetadata?["promptTokenCount"] as? Int
        let outputTokens = usageMetadata?["candidatesTokenCount"] as? Int

        // Extract finish reason (optional)
        let finishReason = firstCandidate["finishReason"] as? String

        logger.debug("Chat request successful, input tokens: \(inputTokens ?? 0), output tokens: \(outputTokens ?? 0)")

        return LLMResponse(
            content: text,
            model: model,
            provider: .gemini,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            finishReason: finishReason
        )
    }

    // MARK: - Private Helpers

    /// Exchanges authorization code for access and refresh tokens.
    ///
    /// - Parameter code: Authorization code from OAuth callback
    /// - Returns: Token bundle with access/refresh tokens and user email
    /// - Throws: `LLMError` if exchange fails
    private func exchangeCodeForTokens(code: String) async throws -> OAuthTokenBundle {
        // Build form body
        let bodyParams = [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "client_secret": Self.clientSecret,
            "code": code,
            "redirect_uri": Self.redirectURI
        ]

        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")

        guard let bodyData = bodyString.data(using: .utf8) else {
            throw LLMError.authenticationFailed(provider: .gemini, detail: "Failed to encode request body")
        }

        // Create request
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        // Execute request
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            logger.error("Token exchange network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Token exchange failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw LLMError.authenticationFailed(provider: .gemini, detail: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse response
        let json: [String: Any]

        do {
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to parse JSON response")
        }

        guard let accessToken = json["access_token"] as? String else {
            throw LLMError.invalidResponse(detail: "Missing access_token in response")
        }

        guard let refreshToken = json["refresh_token"] as? String else {
            throw LLMError.invalidResponse(detail: "Missing refresh_token in response")
        }

        guard let expiresIn = json["expires_in"] as? Int else {
            throw LLMError.invalidResponse(detail: "Missing expires_in in response")
        }

        let expiresAt = Date(timeIntervalSinceNow: TimeInterval(expiresIn))

        // Fetch user email
        let email = try await fetchUserEmail(accessToken: accessToken)

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            email: email,
            clientSecret: Self.clientSecret
        )
    }

    /// Fetches the user's email from Google userinfo API.
    ///
    /// - Parameter accessToken: Valid access token
    /// - Returns: User email address
    /// - Throws: `LLMError` if fetch fails
    private func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: Self.userinfoURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            logger.error("Userinfo request network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Userinfo request failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw LLMError.authenticationFailed(provider: .gemini, detail: "Failed to fetch user email")
        }

        let json: [String: Any]

        do {
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to parse userinfo JSON")
        }

        guard let email = json["email"] as? String, !email.isEmpty else {
            throw LLMError.invalidResponse(detail: "Missing or empty email in userinfo response")
        }

        return email
    }
}

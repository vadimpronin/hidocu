//
//  GeminiProvider.swift
//  HiDocu
//
//  Google Gemini LLM provider implementation using OAuth2 authentication.
//  Uses Cloud Code Assist API (cloudcode-pa.googleapis.com) with the Gemini CLI OAuth client.
//

import Foundation
import os

/// Google Gemini LLM provider strategy.
///
/// Implements OAuth2 authentication flow with client secret (not PKCE).
/// Uses the Cloud Code Assist API endpoint which is accessible with the Gemini CLI OAuth client.
///
/// Key differences from PKCE-based providers:
/// - Uses client_secret instead of PKCE code_verifier
/// - Client secret must be stored in OAuthTokenBundle for refresh operations
/// - Fetches user email from Google userinfo API after token exchange
/// - Requires project ID obtained via loadCodeAssist endpoint
/// - Request body wraps standard Gemini payload in a `request` field with `project` and `model`
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

    // Cloud Code Assist API (used by Gemini CLI, not the public generativelanguage API)
    private static let apiBaseURL = "https://cloudcode-pa.googleapis.com/v1internal"
    private static let userinfoURL = "https://www.googleapis.com/oauth2/v1/userinfo?alt=json"

    // Headers to match the Gemini CLI client identity
    private static let cliUserAgent = "google-api-nodejs-client/9.15.1"
    private static let cliApiClient = "gl-node/22.17.0"
    private static let cliMetadata = "ideType=IDE_UNSPECIFIED,platform=PLATFORM_UNSPECIFIED,pluginType=GEMINI"

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
    /// 7. Fetch project ID via loadCodeAssist endpoint
    ///
    /// - Returns: Token bundle with access/refresh tokens, user email, and project ID
    /// - Throws: `LLMError` if authentication fails
    func authenticate() async throws -> OAuthTokenBundle {
        AppLogger.llm.info("Starting Gemini OAuth authentication flow")

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
            AppLogger.llm.error("OAuth callback failed: \(error.localizedDescription)")
            throw LLMError.authenticationFailed(provider: .gemini, detail: error.localizedDescription)
        }

        // Verify state matches
        guard result.state == state else {
            throw LLMError.authenticationFailed(provider: .gemini, detail: "State parameter mismatch (CSRF protection)")
        }

        AppLogger.llm.debug("Received authorization code, exchanging for tokens")

        // Exchange code for tokens
        let tokenBundle = try await exchangeCodeForTokens(code: result.code)

        // Fetch project ID required for Cloud Code API
        let projectId = try await fetchProjectId(accessToken: tokenBundle.accessToken)
        AppLogger.llm.info("Obtained Cloud Code project ID: \(projectId)")

        let bundleWithProject = OAuthTokenBundle(
            accessToken: tokenBundle.accessToken,
            refreshToken: tokenBundle.refreshToken,
            expiresAt: tokenBundle.expiresAt,
            email: tokenBundle.email,
            projectId: projectId,
            clientSecret: Self.clientSecret
        )

        AppLogger.llm.info("Gemini authentication successful for user: \(tokenBundle.email)")
        return bundleWithProject
    }

    /// Refreshes an expired access token using the refresh token.
    ///
    /// Note: Google may not return a new refresh_token in the response.
    /// If not present, we reuse the existing refresh token.
    /// The project ID is re-fetched using the new access token.
    ///
    /// - Parameter refreshToken: Valid refresh token
    /// - Returns: New token bundle with refreshed access token and project ID
    /// - Throws: `LLMError.tokenRefreshFailed` if refresh fails
    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenBundle {
        AppLogger.llm.info("Refreshing Gemini access token")

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
            AppLogger.llm.error("Token refresh network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Token refresh failed with status \(httpResponse.statusCode): \(errorMessage)")
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

        AppLogger.llm.debug("Token refresh successful, expires at: \(expiresAt)")

        // Fetch user email (we need it for the token bundle)
        let email = try await fetchUserEmail(accessToken: accessToken)

        // Re-fetch project ID with new access token
        let projectId = try await fetchProjectId(accessToken: accessToken)

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            expiresAt: expiresAt,
            email: email,
            projectId: projectId,
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

    /// Fetches available Gemini models from the retrieveUserQuota endpoint.
    ///
    /// Calls the Cloud Code Assist API quota endpoint to get the current list of available models
    /// with their quota information. Extracts model IDs from the response and deduplicates
    /// (removing _vertex variants to show only the base model names).
    ///
    /// - Parameters:
    ///   - accessToken: Valid access token
    ///   - accountId: Account ID (unused, kept for protocol conformance)
    /// - Returns: Sorted array of unique model identifiers
    /// - Throws: `LLMError` if fetch fails
    func fetchModels(accessToken: String, accountId: String?, tokenData: TokenData? = nil) async throws -> [ModelInfo] {
        let url = URL(string: "\(Self.apiBaseURL):retrieveUserQuota")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.cliUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.cliApiClient, forHTTPHeaderField: "X-Goog-Api-Client")
        request.setValue(Self.cliMetadata, forHTTPHeaderField: "Client-Metadata")

        // Use actual project ID from token data; fall back to wildcard
        let projectId = tokenData?.projectId ?? "*"
        let body: [String: Any] = [
            "project": projectId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            AppLogger.llm.error("fetchModels network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("fetchModels failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw LLMError.apiError(provider: .gemini, statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["buckets"] as? [[String: Any]] else {
            throw LLMError.invalidResponse(detail: "Missing buckets in retrieveUserQuota response")
        }

        // Extract unique model IDs from buckets, removing _vertex variants
        var modelIds = Set<String>()
        for bucket in buckets {
            if let modelId = bucket["modelId"] as? String, !modelId.isEmpty {
                // Remove _vertex suffix to avoid duplicates (show base model names only)
                let baseModel = modelId.hasSuffix("_vertex") ? String(modelId.dropLast(7)) : modelId
                modelIds.insert(baseModel)
            }
        }

        let sortedModels = modelIds.sorted()
        AppLogger.llm.info("Fetched \(sortedModels.count) Gemini models from quota endpoint")
        return sortedModels.map { ModelInfo(id: $0, displayName: $0) }
    }

    /// Sends a chat completion request to the Cloud Code Assist API.
    ///
    /// Converts messages to Gemini's format:
    /// - `system` messages -> `systemInstruction` field
    /// - `user` messages -> role `"user"`
    /// - `assistant` messages -> role `"model"`
    ///
    /// The request is wrapped in the Cloud Code format with `project`, `model`, and `request` fields.
    ///
    /// - Parameters:
    ///   - messages: Conversation history
    ///   - model: Model identifier (e.g., "gemini-2.5-flash")
    ///   - accessToken: Valid access token
    ///   - options: Request configuration (max tokens, temperature, system prompt)
    ///   - tokenData: Token data containing the project ID required for Cloud Code API
    /// - Returns: Completed response with content and token usage
    /// - Throws: `LLMError` if request fails
    func chat(
        messages: [LLMMessage],
        model: String,
        accessToken: String,
        options: LLMRequestOptions,
        tokenData: TokenData? = nil
    ) async throws -> LLMResponse {
        AppLogger.llm.info("Sending chat request to Gemini Cloud Code API, model: \(model)")

        // Project ID is required for Cloud Code API
        guard let projectId = tokenData?.projectId, !projectId.isEmpty else {
            throw LLMError.apiError(
                provider: .gemini,
                statusCode: 0,
                message: "Project ID is missing. Please reconnect your Gemini account."
            )
        }

        // Build Cloud Code API URL (RPC-style endpoint)
        let url = URL(string: "\(Self.apiBaseURL):generateContent")!

        // Convert messages to Gemini format
        var contents: [[String: Any]] = []
        var systemInstructions: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                systemInstructions.append(message.content)
            case .user:
                var parts: [[String: Any]] = [["text": message.content]]
                for attachment in message.attachments {
                    parts.append([
                        "inlineData": [
                            "mimeType": attachment.mimeType,
                            "data": attachment.data.base64EncodedString()
                        ]
                    ])
                }
                contents.append([
                    "role": "user",
                    "parts": parts
                ])
            case .assistant:
                contents.append([
                    "role": "model",
                    "parts": [["text": message.content]]
                ])
            }
        }

        // Build inner Gemini request
        var geminiRequest: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "maxOutputTokens": options.maxTokens ?? 65536,
            ]
        ]

        // Add system instruction (prefer options.systemPrompt over message-based system prompts)
        let finalSystemPrompt = options.systemPrompt ?? systemInstructions.joined(separator: "\n\n")
        if !finalSystemPrompt.isEmpty {
            geminiRequest["systemInstruction"] = [
                "parts": [["text": finalSystemPrompt]]
            ]
        }

        // Wrap in Cloud Code API format
        let wrappedBody: [String: Any] = [
            "project": projectId,
            "model": model,
            "request": geminiRequest
        ]

        // Serialize to JSON
        let bodyData: Data

        do {
            bodyData = try JSONSerialization.data(withJSONObject: wrappedBody)
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to serialize request body: \(error.localizedDescription)")
        }

        // Create request with Cloud Code headers
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let hasAttachments = messages.contains { !$0.attachments.isEmpty }
        request.timeoutInterval = hasAttachments ? 600 : 300
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.cliUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.cliApiClient, forHTTPHeaderField: "X-Goog-Api-Client")
        request.setValue(Self.cliMetadata, forHTTPHeaderField: "Client-Metadata")
        request.httpBody = bodyData

        // Execute request
        let (data, response): (Data, URLResponse)

        let requestStart = Date()
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            AppLogger.llm.error("Chat request network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }
        let elapsed = Date().timeIntervalSince(requestStart)
        AppLogger.llm.info("Gemini response received in \(String(format: "%.1f", elapsed))s (\(data.count) bytes)")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        // Handle non-2xx status codes
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Chat request failed with status \(httpResponse.statusCode): \(errorMessage)")

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

        // Cloud Code API may wrap response in a "response" field
        let actualResponse = (json["response"] as? [String: Any]) ?? json

        // Extract content from response
        guard let candidates = actualResponse["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            AppLogger.llm.error("Invalid response structure: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw LLMError.invalidResponse(detail: "Missing or invalid content in response")
        }

        // Extract usage metadata (optional)
        let usageMetadata = actualResponse["usageMetadata"] as? [String: Any]
        let inputTokens = usageMetadata?["promptTokenCount"] as? Int
        let outputTokens = usageMetadata?["candidatesTokenCount"] as? Int

        // Extract finish reason (optional)
        let finishReason = firstCandidate["finishReason"] as? String

        AppLogger.llm.debug("Chat request successful, input tokens: \(inputTokens ?? 0), output tokens: \(outputTokens ?? 0)")

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

    /// Fetches the Google Cloud Project ID required for the Cloud Code API.
    ///
    /// Calls the `loadCodeAssist` endpoint to retrieve the user's project ID.
    /// This is the same mechanism used by the Gemini CLI.
    ///
    /// - Parameter accessToken: Valid access token
    /// - Returns: Cloud AI Companion project ID
    /// - Throws: `LLMError` if fetch fails
    private func fetchProjectId(accessToken: String) async throws -> String {
        let url = URL(string: "\(Self.apiBaseURL):loadCodeAssist")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.cliUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.cliApiClient, forHTTPHeaderField: "X-Goog-Api-Client")
        request.setValue(Self.cliMetadata, forHTTPHeaderField: "Client-Metadata")

        let body: [String: Any] = [
            "metadata": [
                "ideType": "IDE_UNSPECIFIED",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            AppLogger.llm.error("loadCodeAssist network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
            AppLogger.llm.error("Failed to fetch project ID, status \(httpResponse.statusCode): \(errorText)")
            throw LLMError.apiError(
                provider: .gemini,
                statusCode: httpResponse.statusCode,
                message: "Failed to fetch Project ID: \(errorText)"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Failed to parse loadCodeAssist response")
        }

        // Extract project ID — can be a string or an object with "id" field
        if let projectId = json["cloudaicompanionProject"] as? String, !projectId.isEmpty {
            return projectId.trimmingCharacters(in: .whitespaces)
        }

        if let projectMap = json["cloudaicompanionProject"] as? [String: Any],
           let projectId = projectMap["id"] as? String, !projectId.isEmpty {
            return projectId.trimmingCharacters(in: .whitespaces)
        }

        // Code Assist is not enabled, auto-activate it
        AppLogger.llm.info("Code Assist not enabled, activating automatically")

        // Extract default tier ID from allowedTiers
        var tierID = "free-tier" // Default fallback
        if let allowedTiers = json["allowedTiers"] as? [[String: Any]] {
            for tier in allowedTiers {
                if let isDefault = tier["isDefault"] as? Bool, isDefault,
                   let id = tier["id"] as? String, !id.isEmpty {
                    tierID = id
                    AppLogger.llm.debug("Using default tier: \(tierID)")
                    break
                }
            }
        }

        // Activate Code Assist and return the project ID
        return try await activateCodeAssist(accessToken: accessToken, tierID: tierID)
    }

    /// Activates Code Assist by calling the onboardUser endpoint with polling.
    ///
    /// Polls the `onboardUser` endpoint up to 20 times with 3-second intervals,
    /// waiting for the activation to complete and return a project ID.
    ///
    /// - Parameters:
    ///   - accessToken: Valid access token
    ///   - tierID: Tier ID to activate (typically extracted from allowedTiers in loadCodeAssist)
    /// - Returns: Cloud AI Companion project ID after successful activation
    /// - Throws: `LLMError` if activation fails or times out
    private func activateCodeAssist(accessToken: String, tierID: String) async throws -> String {
        AppLogger.llm.info("Activating Code Assist with tier: \(tierID)")

        let url = URL(string: "\(Self.apiBaseURL):onboardUser")!
        let maxAttempts = 20
        let pollInterval = Duration.seconds(3)

        let body: [String: Any] = [
            "tierId": tierID,
            "metadata": [
                "ideType": "IDE_UNSPECIFIED",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw LLMError.apiError(
                provider: .gemini,
                statusCode: 0,
                message: "Failed to serialize onboardUser request body: \(error.localizedDescription)"
            )
        }

        // Poll up to maxAttempts times
        for attempt in 1...maxAttempts {
            AppLogger.llm.debug("Code Assist activation attempt \(attempt)/\(maxAttempts)")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.cliUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(Self.cliApiClient, forHTTPHeaderField: "X-Goog-Api-Client")
            request.setValue(Self.cliMetadata, forHTTPHeaderField: "Client-Metadata")
            request.httpBody = bodyData

            let (data, response): (Data, URLResponse)

            do {
                (data, response) = try await urlSession.data(for: request)
            } catch {
                AppLogger.llm.error("onboardUser network error: \(error.localizedDescription)")
                throw LLMError.networkError(underlying: error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse(detail: "Not an HTTP response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
                AppLogger.llm.error("onboardUser failed with status \(httpResponse.statusCode): \(errorText)")
                throw LLMError.apiError(
                    provider: .gemini,
                    statusCode: httpResponse.statusCode,
                    message: "Code Assist activation failed: \(errorText)"
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLMError.invalidResponse(detail: "Failed to parse onboardUser response")
            }

            // Check if activation is done
            if let done = json["done"] as? Bool, done {
                AppLogger.llm.info("Code Assist activation completed")

                // Extract project ID from response.cloudaicompanionProject
                guard let responseMap = json["response"] as? [String: Any] else {
                    throw LLMError.apiError(
                        provider: .gemini,
                        statusCode: 0,
                        message: "Missing response data in completed onboardUser response"
                    )
                }

                // Handle string format
                if let projectId = responseMap["cloudaicompanionProject"] as? String, !projectId.isEmpty {
                    AppLogger.llm.info("Code Assist activated successfully, project ID: \(projectId)")
                    return projectId.trimmingCharacters(in: .whitespaces)
                }

                // Handle object format with "id" field
                if let projectMap = responseMap["cloudaicompanionProject"] as? [String: Any],
                   let projectId = projectMap["id"] as? String, !projectId.isEmpty {
                    AppLogger.llm.info("Code Assist activated successfully, project ID: \(projectId)")
                    return projectId.trimmingCharacters(in: .whitespaces)
                }

                // Activation completed but project ID not found
                throw LLMError.apiError(
                    provider: .gemini,
                    statusCode: 0,
                    message: "Code Assist activation completed but project ID not found in response"
                )
            }

            // Not done yet, wait before next attempt (unless this is the last attempt)
            if attempt < maxAttempts {
                AppLogger.llm.debug("Code Assist activation in progress, waiting 3 seconds...")
                try await Task.sleep(for: pollInterval)
            }
        }

        // Exceeded max attempts
        AppLogger.llm.error("Code Assist activation timed out after \(maxAttempts) attempts")
        throw LLMError.apiError(
            provider: .gemini,
            statusCode: 0,
            message: "Code Assist activation timed out. Please try again."
        )
    }

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
            AppLogger.llm.error("Token exchange network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Token exchange failed with status \(httpResponse.statusCode): \(errorMessage)")
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
            AppLogger.llm.error("Userinfo request network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Userinfo request failed with status \(httpResponse.statusCode): \(errorMessage)")
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

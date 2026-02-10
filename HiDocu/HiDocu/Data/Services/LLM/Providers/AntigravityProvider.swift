//
//  AntigravityProvider.swift
//  HiDocu
//
//  Antigravity LLM provider implementation using Google OAuth2 authentication.
//  Uses Cloud Code Assist API (cloudcode-pa.googleapis.com) with the Antigravity OAuth client.
//

import Foundation
import CommonCrypto
import os

/// Antigravity LLM provider strategy.
///
/// Uses Google OAuth2 with client_secret (same pattern as Gemini CLI) but with
/// different credentials and additional OAuth scopes for Antigravity.
/// Communicates via the Cloud Code Assist API (daily endpoint).
final class AntigravityProvider: LLMProviderStrategy, Sendable {
    // MARK: - OAuth Configuration

    private static let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private static let clientSecret = "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"
    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let redirectURI = "http://localhost:51121/oauth-callback"
    private static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs"
    ]
    private static let callbackPort: UInt16 = 51121
    private static let callbackPath = "/oauth-callback"

    // MARK: - API Configuration

    private static let apiBaseURL = "https://daily-cloudcode-pa.googleapis.com/v1internal"
    private static let userinfoURL = "https://www.googleapis.com/oauth2/v1/userinfo?alt=json"

    // Headers for loadCodeAssist (auth flow) — match constants.go
    private static let authUserAgent = "google-api-nodejs-client/9.15.1"
    private static let authApiClient = "google-cloud-sdk vscode_cloudshelleditor/0.1"
    private static let authClientMetadata = #"{"ideType":"IDE_UNSPECIFIED","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}"#

    // User-Agent for API calls (chat, models) — match executor defaultAntigravityAgent
    private static let apiUserAgent = "antigravity/1.104.0 darwin/arm64"

    // MARK: - Properties

    let provider: LLMProvider = .antigravity
    private let urlSession: URLSession

    // MARK: - Initialization

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - LLMProviderStrategy

    func authenticate() async throws -> OAuthTokenBundle {
        AppLogger.llm.info("Starting Antigravity OAuth authentication flow")

        let state = try PKCEHelper.generateState()

        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw LLMError.authenticationFailed(provider: .antigravity, detail: "Failed to construct authorization URL")
        }

        let server = OAuthCallbackServer(port: Self.callbackPort, callbackPath: Self.callbackPath, provider: .antigravity)
        let result: OAuthResult

        do {
            result = try await server.awaitCallback(authorizationURL: authURL)
        } catch {
            AppLogger.llm.error("OAuth callback failed: \(error.localizedDescription)")
            throw LLMError.authenticationFailed(provider: .antigravity, detail: error.localizedDescription)
        }

        guard result.state == state else {
            throw LLMError.authenticationFailed(provider: .antigravity, detail: "State parameter mismatch (CSRF protection)")
        }

        AppLogger.llm.debug("Received authorization code, exchanging for tokens")

        let tokenBundle = try await exchangeCodeForTokens(code: result.code)

        let projectId = try await fetchProjectId(accessToken: tokenBundle.accessToken)
        AppLogger.llm.info("Obtained Antigravity project ID: \(projectId)")

        let bundleWithProject = OAuthTokenBundle(
            accessToken: tokenBundle.accessToken,
            refreshToken: tokenBundle.refreshToken,
            expiresAt: tokenBundle.expiresAt,
            email: tokenBundle.email,
            projectId: projectId,
            clientSecret: Self.clientSecret
        )

        AppLogger.llm.info("Antigravity authentication successful for user: \(tokenBundle.email)")
        return bundleWithProject
    }

    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenBundle {
        AppLogger.llm.info("Refreshing Antigravity access token")

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
            throw LLMError.tokenRefreshFailed(provider: .antigravity, detail: "Failed to encode request body")
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("oauth2.googleapis.com", forHTTPHeaderField: "Host")
        request.httpBody = bodyData

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
            throw LLMError.tokenRefreshFailed(provider: .antigravity, detail: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

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

        let newRefreshToken = (json["refresh_token"] as? String) ?? refreshToken
        let expiresAt = Date(timeIntervalSinceNow: TimeInterval(expiresIn))

        let email = try await fetchUserEmail(accessToken: accessToken)
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

    func isTokenExpired(_ expiresAt: Date) -> Bool {
        expiresAt.timeIntervalSinceNow < 300
    }

    /// Excluded model IDs that are internal/experimental (matching CLIProxyAPI filtering).
    private static let excludedModels: Set<String> = [
        "chat_20706", "chat_23310", "gemini-2.5-flash-thinking", "gemini-3-pro-low", "gemini-2.5-pro"
    ]

    func fetchModels(accessToken: String, accountId: String?, tokenData: TokenData? = nil) async throws -> [ModelInfo] {
        let url = URL(string: "\(Self.apiBaseURL):fetchAvailableModels")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            AppLogger.llm.error("fetchAvailableModels network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("fetchAvailableModels failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw LLMError.apiError(provider: .antigravity, statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Missing models in fetchAvailableModels response")
        }

        let modelIds = models.keys
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !Self.excludedModels.contains($0) }
            .sorted()

        AppLogger.llm.info("Fetched \(modelIds.count) Antigravity models")

        var results = modelIds.map { ModelInfo(id: $0, displayName: $0, supportsText: true, supportsAudio: true, supportsImage: true) }

        // Fetch token limits from the models API and merge into results
        let limits = await fetchModelLimits(accessToken: accessToken)
        if !limits.isEmpty {
            results = results.map { info in
                guard let limit = limits[info.id] else { return info }
                var updated = info
                updated.maxInputTokens = limit.inputTokenLimit
                updated.maxOutputTokens = limit.outputTokenLimit
                return updated
            }
        }

        return results
    }

    /// Fetches model metadata (token limits) from the Google AI models API.
    /// Returns a dictionary keyed by model ID (without `models/` prefix).
    /// Non-fatal: returns empty dictionary on failure.
    private func fetchModelLimits(accessToken: String) async -> [String: (inputTokenLimit: Int, outputTokenLimit: Int)] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return [:] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                AppLogger.llm.debug("fetchModelLimits: non-2xx response, skipping token limits")
                return [:]
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                return [:]
            }

            var result: [String: (inputTokenLimit: Int, outputTokenLimit: Int)] = [:]
            for model in models {
                guard let name = model["name"] as? String,
                      let inputLimit = model["inputTokenLimit"] as? Int,
                      let outputLimit = model["outputTokenLimit"] as? Int else { continue }
                // Strip "models/" prefix
                let modelId = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                result[modelId] = (inputTokenLimit: inputLimit, outputTokenLimit: outputLimit)
            }
            AppLogger.llm.debug("fetchModelLimits: got limits for \(result.count) models")
            return result
        } catch {
            AppLogger.llm.debug("fetchModelLimits failed (non-fatal): \(error.localizedDescription)")
            return [:]
        }
    }

    func chat(
        messages: [LLMMessage],
        model: String,
        accessToken: String,
        options: LLMRequestOptions,
        tokenData: TokenData? = nil
    ) async throws -> LLMResponse {
        AppLogger.llm.info("Sending chat request to Antigravity API, model: \(model)")

        guard let projectId = tokenData?.projectId, !projectId.isEmpty else {
            throw LLMError.apiError(
                provider: .antigravity,
                statusCode: 0,
                message: "Project ID is missing. Please reconnect your Antigravity account."
            )
        }

        let url = URL(string: "\(Self.apiBaseURL):generateContent")!

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

        var geminiRequest: [String: Any] = [
            "contents": contents
        ]

        let finalSystemPrompt = options.systemPrompt ?? systemInstructions.joined(separator: "\n\n")
        if !finalSystemPrompt.isEmpty {
            geminiRequest["systemInstruction"] = [
                "parts": [["text": finalSystemPrompt]]
            ]
        }

        // Add sessionId matching generateStableSessionID in executor
        geminiRequest["sessionId"] = generateStableSessionID(contents: contents)

        // Build body matching geminiToAntigravity() in executor
        let wrappedBody: [String: Any] = [
            "project": projectId,
            "model": model,
            "userAgent": "antigravity",
            "requestType": "agent",
            "requestId": "agent-\(UUID().uuidString.lowercased())",
            "request": geminiRequest
        ]

        let bodyData: Data

        do {
            bodyData = try JSONSerialization.data(withJSONObject: wrappedBody)
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to serialize request body: \(error.localizedDescription)")
        }

        // Headers match executor buildRequest — only Authorization, Content-Type, User-Agent, Accept
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = bodyData

        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            AppLogger.llm.error("Chat request network error: \(error.localizedDescription)")
            throw LLMError.networkError(underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse(detail: "Not an HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.llm.error("Chat request failed with status \(httpResponse.statusCode): \(errorMessage)")

            if httpResponse.statusCode == 429 {
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0) }
                throw LLMError.rateLimited(provider: .antigravity, retryAfter: retryAfter)
            }

            throw LLMError.apiError(provider: .antigravity, statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let json: [String: Any]

        do {
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to parse JSON response")
        }

        // Cloud Code API may wrap response in a "response" field
        let actualResponse = (json["response"] as? [String: Any]) ?? json

        guard let candidates = actualResponse["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            AppLogger.llm.error("Invalid response structure: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw LLMError.invalidResponse(detail: "Missing or invalid content in response")
        }

        let usageMetadata = actualResponse["usageMetadata"] as? [String: Any]
        let inputTokens = usageMetadata?["promptTokenCount"] as? Int
        let outputTokens = usageMetadata?["candidatesTokenCount"] as? Int
        let finishReason = firstCandidate["finishReason"] as? String

        AppLogger.llm.debug("Chat request successful, input tokens: \(inputTokens ?? 0), output tokens: \(outputTokens ?? 0)")

        return LLMResponse(
            content: text,
            model: model,
            provider: .antigravity,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            finishReason: finishReason
        )
    }

    // MARK: - Private Helpers

    private func fetchProjectId(accessToken: String) async throws -> String {
        let url = URL(string: "\(Self.apiBaseURL):loadCodeAssist")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.authUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.authApiClient, forHTTPHeaderField: "X-Goog-Api-Client")
        request.setValue(Self.authClientMetadata, forHTTPHeaderField: "Client-Metadata")

        let body: [String: Any] = [
            "metadata": [
                "ideType": "ANTIGRAVITY",
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
                provider: .antigravity,
                statusCode: httpResponse.statusCode,
                message: "Failed to fetch Project ID: \(errorText)"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Failed to parse loadCodeAssist response")
        }

        if let projectId = json["cloudaicompanionProject"] as? String, !projectId.isEmpty {
            return projectId.trimmingCharacters(in: .whitespaces)
        }

        if let projectMap = json["cloudaicompanionProject"] as? [String: Any],
           let projectId = projectMap["id"] as? String, !projectId.isEmpty {
            return projectId.trimmingCharacters(in: .whitespaces)
        }

        // Code Assist is not enabled - auto-activate it
        AppLogger.llm.info("Code Assist not enabled, attempting auto-activation")

        // Extract default tier ID from allowedTiers
        var tierID = "free-tier" // Fallback
        if let allowedTiers = json["allowedTiers"] as? [[String: Any]] {
            for tier in allowedTiers {
                if let isDefault = tier["isDefault"] as? Bool, isDefault,
                   let id = tier["id"] as? String, !id.isEmpty {
                    tierID = id
                    break
                }
            }
        }

        AppLogger.llm.debug("Using tier ID: \(tierID) for Code Assist activation")
        return try await activateCodeAssist(accessToken: accessToken, tierID: tierID)
    }

    /// Activates Code Assist for the user by calling the onboardUser API and polling until activation is complete.
    ///
    /// - Parameters:
    ///   - accessToken: OAuth access token for authentication.
    ///   - tierID: The tier ID to activate (typically extracted from loadCodeAssist's allowedTiers).
    /// - Returns: The activated project ID.
    /// - Throws: `LLMError.networkError` on network failure, `LLMError.apiError` on API error or timeout.
    private func activateCodeAssist(accessToken: String, tierID: String) async throws -> String {
        let url = URL(string: "\(Self.apiBaseURL):onboardUser")!

        let body: [String: Any] = [
            "tierId": tierID,
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw LLMError.invalidResponse(detail: "Failed to serialize onboardUser request: \(error.localizedDescription)")
        }

        let maxAttempts = 20
        let sleepDuration = Duration.seconds(3)

        AppLogger.llm.info("Starting Code Assist activation with tier: \(tierID), max attempts: \(maxAttempts)")

        for attempt in 1...maxAttempts {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(Self.authUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(Self.authApiClient, forHTTPHeaderField: "X-Goog-Api-Client")
            request.setValue(Self.authClientMetadata, forHTTPHeaderField: "Client-Metadata")
            request.httpBody = bodyData

            let (data, response): (Data, URLResponse)

            do {
                (data, response) = try await urlSession.data(for: request)
            } catch {
                AppLogger.llm.error("onboardUser network error (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription)")
                throw LLMError.networkError(underlying: error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.invalidResponse(detail: "Not an HTTP response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorText = String(data: data, encoding: .utf8) ?? "Unknown"
                AppLogger.llm.error("onboardUser failed with status \(httpResponse.statusCode): \(errorText)")
                throw LLMError.apiError(
                    provider: .antigravity,
                    statusCode: httpResponse.statusCode,
                    message: "Code Assist activation failed: \(errorText)"
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLMError.invalidResponse(detail: "Failed to parse onboardUser response")
            }

            // Check if activation is complete
            if let done = json["done"] as? Bool, done {
                AppLogger.llm.info("Code Assist activation completed on attempt \(attempt)")

                // Extract project ID from response.cloudaicompanionProject
                guard let responseData = json["response"] as? [String: Any] else {
                    throw LLMError.apiError(
                        provider: .antigravity,
                        statusCode: 0,
                        message: "Missing response data in completed onboardUser response"
                    )
                }

                // Handle both string and object formats
                if let projectId = responseData["cloudaicompanionProject"] as? String, !projectId.isEmpty {
                    AppLogger.llm.info("Code Assist activated successfully, project ID: \(projectId)")
                    return projectId.trimmingCharacters(in: .whitespaces)
                }

                if let projectMap = responseData["cloudaicompanionProject"] as? [String: Any],
                   let projectId = projectMap["id"] as? String, !projectId.isEmpty {
                    AppLogger.llm.info("Code Assist activated successfully, project ID: \(projectId)")
                    return projectId.trimmingCharacters(in: .whitespaces)
                }

                throw LLMError.apiError(
                    provider: .antigravity,
                    statusCode: 0,
                    message: "Code Assist activation completed but project ID not found in response"
                )
            }

            // Not done yet, continue polling
            AppLogger.llm.debug("Code Assist activation in progress (attempt \(attempt)/\(maxAttempts)), polling again...")
            if attempt < maxAttempts {
                try await Task.sleep(for: sleepDuration)
            }
        }

        // Timeout after max attempts
        AppLogger.llm.error("Code Assist activation timed out after \(maxAttempts) attempts")
        throw LLMError.apiError(
            provider: .antigravity,
            statusCode: 0,
            message: "Code Assist activation timed out. Please try again."
        )
    }

    private func exchangeCodeForTokens(code: String) async throws -> OAuthTokenBundle {
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
            throw LLMError.authenticationFailed(provider: .antigravity, detail: "Failed to encode request body")
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

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
            throw LLMError.authenticationFailed(provider: .antigravity, detail: "HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

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

        let email = try await fetchUserEmail(accessToken: accessToken)

        return OAuthTokenBundle(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            email: email,
            clientSecret: Self.clientSecret
        )
    }

    /// Generates a stable session ID from the first user message (matches Go generateStableSessionID).
    private func generateStableSessionID(contents: [[String: Any]]) -> String {
        for content in contents {
            if (content["role"] as? String) == "user",
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String,
               !text.isEmpty {
                var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
                text.data(using: .utf8)!.withUnsafeBytes { ptr in
                    _ = CC_SHA256(ptr.baseAddress, CC_LONG(ptr.count), &hash)
                }
                // Take first 8 bytes as big-endian UInt64, mask to positive Int64
                let value = hash[0..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } & 0x7FFFFFFFFFFFFFFF
                return "-\(value)"
            }
        }
        // Fallback: random session ID (matches generateSessionID in Go)
        return "-\(Int64.random(in: 0..<9_000_000_000_000_000_000))"
    }

    private func fetchUserEmail(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: Self.userinfoURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

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
            throw LLMError.authenticationFailed(provider: .antigravity, detail: "Failed to fetch user email")
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

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmservice", category: "AntigravityProvider")

/// Provider implementation for Antigravity (Google Cloud with project wrapping)
struct AntigravityProvider: InternalProvider {
    let provider: LLMProvider = .antigravity
    let supportsNonStreaming: Bool = false

    /// Project ID obtained via loadCodeAssist during OAuth
    let projectId: String

    private static let streamURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse")!

    // MARK: - Request Building

    func buildStreamRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        credentials: LLMCredentials,
        traceId: String
    ) throws -> URLRequest {
        // Build fully wrapped Antigravity request (includes envelope, session ID, no safety settings)
        let body = AntigravityRequestBuilder.buildRequest(
            modelName: modelId,
            messages: messages,
            thinking: thinking,
            projectId: projectId
        )

        var request = URLRequest(url: Self.streamURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 600
        applyHeaders(to: &request, credentials: credentials)
        return request
    }

    func buildNonStreamRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        credentials: LLMCredentials,
        traceId: String
    ) throws -> URLRequest {
        throw LLMServiceError(
            traceId: traceId,
            message: "Antigravity does not support non-streaming requests"
        )
    }

    // MARK: - Response Parsing

    func parseResponse(data: Data, traceId: String) throws -> LLMResponse {
        throw LLMServiceError(
            traceId: traceId,
            message: "Antigravity does not support non-streaming responses"
        )
    }

    func createStreamParser() -> Any {
        AntigravityStreamParser()
    }

    func parseStreamLine(_ line: String, parser: inout Any) -> [LLMChatChunk] {
        guard let agParser = parser as? AntigravityStreamParser else { return [] }
        let chunks = agParser.parseSSELine(line)
        return chunks
    }

    // MARK: - Models

    func listModels(credentials: LLMCredentials, httpClient: HTTPClient) async throws -> [LLMModelInfo] {
        // 1. Fetch available model IDs from user quota
        let modelIds: [String]
        do {
            modelIds = try await AntigravityQuotaFetcher.fetchAvailableModelIds(
                projectId: projectId,
                credentials: credentials,
                httpClient: httpClient
            )
        } catch {
            logger.warning("Failed to fetch model IDs from quota, using fallback: \(error.localizedDescription)")
            let catalog = await GeminiModelCatalog.shared.getCatalog(httpClient: httpClient)
            var models = catalog.values.map { $0.withNonStreamingDisabled() }
            models.append(Self.claudeSonnetFallback)
            return models.sorted { $0.id < $1.id }
        }

        // 2. Enrich with catalog data
        let catalog = await GeminiModelCatalog.shared.getCatalog(httpClient: httpClient)

        return modelIds.map { modelId in
            // Claude models proxied by Antigravity
            if modelId.lowercased().contains("claude") {
                return Self.claudeModelInfo(for: modelId)
            }

            if let entry = catalog[modelId] {
                return entry.withNonStreamingDisabled()
            }

            return LLMModelInfo(
                id: modelId,
                displayName: LLMModelInfo.formatDisplayName(from: modelId),
                supportsText: true, supportsImage: true,
                supportsNonStreaming: false
            )
        }
    }

    // MARK: - Claude Model Helpers

    private static let claudeSonnetFallback = LLMModelInfo(
        id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5 (via Antigravity)",
        supportsText: true, supportsImage: true,
        supportsThinking: true, supportsTools: true,
        supportsNonStreaming: false,
        maxInputTokens: 200_000, maxOutputTokens: 16_384
    )

    private static func claudeModelInfo(for modelId: String) -> LLMModelInfo {
        LLMModelInfo(
            id: modelId,
            displayName: LLMModelInfo.formatDisplayName(from: modelId) + " (via Antigravity)",
            supportsText: true, supportsImage: true,
            supportsThinking: true, supportsTools: true,
            supportsNonStreaming: false,
            maxInputTokens: 200_000, maxOutputTokens: 16_384
        )
    }

    // MARK: - Headers

    private func applyHeaders(to request: inout URLRequest, credentials: LLMCredentials) {
        let token = credentials.accessToken ?? ""
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("antigravity/1.104.0 darwin/arm64", forHTTPHeaderField: "User-Agent")
        request.setValue("google-cloud-sdk vscode_cloudshelleditor/0.1", forHTTPHeaderField: "X-Goog-Api-Client")
        let metadata = "{\"ideType\":\"IDE_UNSPECIFIED\",\"platform\":\"PLATFORM_UNSPECIFIED\",\"pluginType\":\"GEMINI\"}"
        request.setValue(metadata, forHTTPHeaderField: "Client-Metadata")
    }
}

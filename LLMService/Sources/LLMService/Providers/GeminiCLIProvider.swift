import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmservice", category: "GeminiCLIProvider")

/// Provider implementation for GeminiCLI (Google Cloud Gemini API)
struct GeminiCLIProvider: InternalProvider {
    let provider: LLMProvider = .geminiCLI
    let supportsNonStreaming: Bool = true

    /// Project ID obtained via loadCodeAssist during OAuth
    let projectId: String

    private static let streamURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse")!
    private static let nonStreamURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:generateContent")!

    // MARK: - Request Building

    func buildStreamRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        credentials: LLMCredentials,
        traceId: String
    ) throws -> URLRequest {
        let body = buildBody(modelId: modelId, messages: messages, thinking: thinking)

        var request = URLRequest(url: Self.streamURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
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
        let body = buildBody(modelId: modelId, messages: messages, thinking: thinking)

        var request = URLRequest(url: Self.nonStreamURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyHeaders(to: &request, credentials: credentials)
        return request
    }

    private func buildBody(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?
    ) -> [String: Any] {
        var fullBody = GoogleCloudRequestBuilder.buildRequest(
            modelName: modelId,
            messages: messages,
            thinking: thinking
        )
        // Add project field required by cloudcode-pa API
        fullBody["project"] = projectId
        return fullBody
    }

    // MARK: - Response Parsing

    func parseResponse(data: Data, traceId: String) throws -> LLMResponse {
        try GoogleCloudResponseParser.parseResponse(data: data, traceId: traceId)
    }

    func createStreamParser() -> Any {
        GoogleCloudStreamParser()
    }

    func parseStreamLine(_ line: String, parser: inout Any) -> [LLMChatChunk] {
        guard let gcParser = parser as? GoogleCloudStreamParser else { return [] }
        let chunks = gcParser.parseSSELine(line)
        return chunks
    }

    // MARK: - Models

    func listModels(credentials: LLMCredentials, httpClient: HTTPClient) async throws -> [LLMModelInfo] {
        // 1. Fetch available model IDs from user quota
        let modelIds: [String]
        do {
            modelIds = try await GoogleCloudQuotaFetcher.fetchAvailableModelIds(
                projectId: projectId,
                credentials: credentials,
                httpClient: httpClient,
                userAgent: "google-api-nodejs-client/9.15.1",
                apiClient: "gl-node/22.17.0"
            )
        } catch {
            logger.warning("Failed to fetch model IDs from quota, using catalog fallback: \(error.localizedDescription)")
            let catalog = await GeminiModelCatalog.shared.getCatalog(httpClient: httpClient)
            return catalog.values.sorted { $0.id < $1.id }
        }

        // 2. Enrich with catalog data (display names, capabilities, token limits)
        let catalog = await GeminiModelCatalog.shared.getCatalog(httpClient: httpClient)

        return modelIds.map { modelId in
            if let entry = catalog[modelId] {
                return entry
            }
            // Model exists in quota but not in catalog — create a basic entry
            return LLMModelInfo(
                id: modelId,
                displayName: LLMModelInfo.formatDisplayName(from: modelId),
                supportsText: true,
                supportsImage: true,
                supportsAudio: true,
                supportsVideo: true,
                supportsTools: true
            )
        }
    }

    // MARK: - Headers

    private func applyHeaders(to request: inout URLRequest, credentials: LLMCredentials) {
        let token = credentials.accessToken ?? ""
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("google-api-nodejs-client/9.15.1", forHTTPHeaderField: "User-Agent")
        request.setValue("gl-node/22.17.0", forHTTPHeaderField: "X-Goog-Api-Client")
        request.setValue("ideType=IDE_UNSPECIFIED,platform=PLATFORM_UNSPECIFIED,pluginType=GEMINI", forHTTPHeaderField: "Client-Metadata")
    }
}

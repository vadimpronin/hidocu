import Foundation

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

    func listModels() -> [LLMModelInfo] {
        [
            LLMModelInfo(
                id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 65_536
            ),
            LLMModelInfo(
                id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 65_536
            ),
            LLMModelInfo(
                id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 8_192
            ),
        ]
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

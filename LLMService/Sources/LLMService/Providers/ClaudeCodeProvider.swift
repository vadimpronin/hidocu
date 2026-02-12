import Foundation

/// Provider implementation for Claude Code (Anthropic Messages API)
struct ClaudeCodeProvider: InternalProvider {
    let provider: LLMProvider = .claudeCode
    let supportsNonStreaming: Bool = true

    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let betaFeatures = [
        "claude-code-20250219",
        "oauth-2025-04-20",
        "interleaved-thinking-2025-05-14",
        "fine-grained-tool-streaming-2025-05-14",
        "prompt-caching-2024-07-31",
    ].joined(separator: ",")

    // MARK: - Request Building

    func buildStreamRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        credentials: LLMCredentials,
        traceId: String
    ) throws -> URLRequest {
        let body = ClaudeRequestBuilder.buildRequest(
            modelId: modelId,
            messages: messages,
            thinking: thinking,
            stream: true
        )

        var request = URLRequest(url: Self.messagesURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyHeaders(to: &request, credentials: credentials, stream: true)
        request.timeoutInterval = 600
        return request
    }

    func buildNonStreamRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        credentials: LLMCredentials,
        traceId: String
    ) throws -> URLRequest {
        let body = ClaudeRequestBuilder.buildRequest(
            modelId: modelId,
            messages: messages,
            thinking: thinking,
            stream: false
        )

        var request = URLRequest(url: Self.messagesURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyHeaders(to: &request, credentials: credentials, stream: false)
        request.timeoutInterval = 600
        return request
    }

    // MARK: - Response Parsing

    func parseResponse(data: Data, traceId: String) throws -> LLMResponse {
        try ClaudeResponseParser.parseResponse(data: data, traceId: traceId)
    }

    func createStreamParser() -> Any {
        ClaudeStreamParser()
    }

    func parseStreamLine(_ line: String, parser: inout Any) -> [LLMChatChunk] {
        guard let claudeParser = parser as? ClaudeStreamParser else { return [] }
        return claudeParser.parseStreamLine(line)
    }

    // MARK: - Models

    func listModels(credentials: LLMCredentials, httpClient: HTTPClient) async throws -> [LLMModelInfo] {
        [
            LLMModelInfo(
                id: "claude-sonnet-4-5-20250929", displayName: "Claude Sonnet 4.5",
                supportsText: true, supportsImage: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 200_000, maxOutputTokens: 16_384
            ),
            LLMModelInfo(
                id: "claude-opus-4-6", displayName: "Claude Opus 4.6",
                supportsText: true, supportsImage: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 200_000, maxOutputTokens: 16_384
            ),
            LLMModelInfo(
                id: "claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5",
                supportsText: true, supportsImage: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 200_000, maxOutputTokens: 16_384
            ),
        ]
    }

    // MARK: - Headers

    private func applyHeaders(to request: inout URLRequest, credentials: LLMCredentials, stream: Bool) {
        let token = credentials.accessToken ?? credentials.apiKey ?? ""
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.betaFeatures, forHTTPHeaderField: "Anthropic-Beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "Anthropic-Version")
        request.setValue("true", forHTTPHeaderField: "Anthropic-Dangerous-Direct-Browser-Access")
        request.setValue("cli", forHTTPHeaderField: "X-App")
        request.setValue("stream", forHTTPHeaderField: "X-Stainless-Helper-Method")
        request.setValue("0", forHTTPHeaderField: "X-Stainless-Retry-Count")
        request.setValue("v24.3.0", forHTTPHeaderField: "X-Stainless-Runtime-Version")
        request.setValue("0.55.1", forHTTPHeaderField: "X-Stainless-Package-Version")
        request.setValue("node", forHTTPHeaderField: "X-Stainless-Runtime")
        request.setValue("js", forHTTPHeaderField: "X-Stainless-Lang")
        request.setValue("arm64", forHTTPHeaderField: "X-Stainless-Arch")
        request.setValue("MacOS", forHTTPHeaderField: "X-Stainless-Os")
        request.setValue("600", forHTTPHeaderField: "X-Stainless-Timeout")
        request.setValue("claude-cli/1.0.83 (external, cli)", forHTTPHeaderField: "User-Agent")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
    }
}

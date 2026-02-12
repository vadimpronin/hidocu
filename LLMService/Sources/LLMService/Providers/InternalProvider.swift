import Foundation

/// Internal protocol for provider-specific request building and response parsing.
///
/// Each LLM provider (Claude, GeminiCLI, Antigravity) implements this protocol
/// to handle its specific API format, headers, and response parsing.
protocol InternalProvider: Sendable {
    var provider: LLMProvider { get }

    /// Build a URLRequest for streaming chat
    func buildStreamRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        credentials: LLMCredentials,
        traceId: String
    ) throws -> URLRequest

    /// Build a URLRequest for non-streaming chat
    func buildNonStreamRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        credentials: LLMCredentials,
        traceId: String
    ) throws -> URLRequest

    /// Parse non-streaming response data into LLMResponse
    func parseResponse(data: Data, traceId: String) throws -> LLMResponse

    /// Create a stream parser for this provider (type-erased; cast in parseStreamLine)
    func createStreamParser() -> Any

    /// Parse a single SSE line using the provider's stream parser.
    /// The parser is passed as inout to allow stateful mutation across lines.
    func parseStreamLine(_ line: String, parser: inout Any) -> [LLMChatChunk]

    /// Whether this provider supports non-streaming requests
    var supportsNonStreaming: Bool { get }

    /// Return available models for this provider.
    /// Providers that support dynamic fetching use credentials and httpClient
    /// to query available models. Providers with static model lists may ignore these parameters.
    func listModels(credentials: LLMCredentials, httpClient: HTTPClient) async throws -> [LLMModelInfo]
}

import XCTest
@testable import LLMService

final class SmartChatTests: XCTestCase {
    func testSmartChatAggregatesStream() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        // Prepare SSE response with text content
        // Use \n line endings (no \r) since chatStream splits on \n
        // and each line is passed individually to parseStreamLine which calls parseSSEText
        let sseResponse = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello \"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"World\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_delta",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"input_tokens\":5,\"output_tokens\":10}}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
            "",
        ].joined(separator: "\n")

        mockClient.enqueue(.sse(sseResponse))

        let launcher = MockOAuthLauncher()
        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: launcher
        )

        let response = try await service.chat(
            modelId: "claude-3",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Hello World")
        XCTAssertEqual(mockClient.requestCount, 1)
    }

    func testSmartChatPreservesUnicode() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        let sseResponse = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Ответ: 42 🎉\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_delta",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"input_tokens\":5,\"output_tokens\":10}}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
            "",
        ].joined(separator: "\n")

        mockClient.enqueue(.sse(sseResponse))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chat(
            modelId: "claude-3",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Ответ: 42 🎉")
        XCTAssertFalse(response.fullText.contains("\u{FFFD}"), "Response should not contain replacement characters")
    }
}

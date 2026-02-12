import XCTest
@testable import LLMService

final class TokenRefreshTests: XCTestCase {
    func testAutoRefreshOn401() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "old-token", refreshToken: "refresh-token")
        )

        // First request returns 401
        mockClient.enqueue(.error(401, message: "Unauthorized"))

        // Refresh token request succeeds
        mockClient.enqueue(.json([
            "access_token": "new-token",
            "refresh_token": "new-refresh",
            "expires_in": 3600,
            "account": ["email_address": "test@example.com"],
            "organization": ["uuid": "org-1"]
        ]))

        // Retry with new token - stream response using \n line endings
        let sseResponse = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"OK\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_delta",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"input_tokens\":5,\"output_tokens\":1}}",
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
            messages: [LLMMessage(role: .user, content: [.text("hi")])]
        )

        // Should have made 3 requests: original(401), refresh, retry
        XCTAssertEqual(mockClient.requestCount, 3)
        XCTAssertEqual(response.fullText, "OK")

        // Verify the 3rd request has the new token
        let retryRequest = mockClient.capturedRequests[2]
        XCTAssertEqual(retryRequest.value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
    }
}

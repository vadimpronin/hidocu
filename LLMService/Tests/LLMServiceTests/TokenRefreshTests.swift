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

        // Retry with new token - non-streaming JSON response (Claude uses non-streaming path)
        mockClient.enqueue(.json([
            "id": "msg-1",
            "type": "message",
            "role": "assistant",
            "model": "claude-3",
            "content": [
                ["type": "text", "text": "OK"]
            ],
            "usage": [
                "input_tokens": 5,
                "output_tokens": 1
            ]
        ] as [String: Any]))

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

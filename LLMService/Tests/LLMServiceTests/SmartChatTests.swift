import XCTest
@testable import LLMService

final class SmartChatTests: XCTestCase {
    func testSmartChatAggregatesStream() async throws {
        let mockClient = MockHTTPClient()
        // Use Antigravity (streaming-only) to test stream aggregation path
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        // Google Cloud SSE format with two text chunks
        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello \"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"World\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: [DONE]",
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
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Hello World")
        XCTAssertEqual(mockClient.requestCount, 1)
    }

    func testSmartChatPreservesUnicode() async throws {
        let mockClient = MockHTTPClient()
        // Use Antigravity (streaming-only) to test unicode preservation in stream aggregation
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\\u041e\\u0442\\u0432\\u0435\\u0442: 42 \\ud83c\\udf89\"}],\"role\":\"model\"}}]}",
            "",
            "data: [DONE]",
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
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Ответ: 42 🎉")
        XCTAssertFalse(response.fullText.contains("\u{FFFD}"), "Response should not contain replacement characters")
    }

    // MARK: - Non-streaming path tests

    func testChatUsesNonStreamingPathForGemini() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .geminiCLI,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .geminiCLI, metadata: ["project_id": "test-project"])

        // Enqueue a non-streaming Google Cloud JSON response
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "Hello from Gemini"]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ],
            "usageMetadata": [
                "promptTokenCount": 10,
                "candidatesTokenCount": 5
            ],
            "responseId": "resp-123",
            "modelVersion": "gemini-2.0-flash"
        ]

        mockClient.enqueue(.json(responseJSON))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Hello from Gemini")
        XCTAssertEqual(mockClient.requestCount, 1)

        // Verify the URL is the non-streaming endpoint (generateContent, not streamGenerateContent)
        let capturedURL = mockClient.capturedRequests.first?.url?.absoluteString ?? ""
        XCTAssertTrue(capturedURL.contains("generateContent"), "Should use non-streaming generateContent URL")
        XCTAssertFalse(capturedURL.contains("streamGenerateContent"), "Should NOT use streaming URL")
    }

    func testChatFallsBackToStreamForAntigravity() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        // Antigravity uses streaming — enqueue SSE response with Google Cloud format
        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: [DONE]",
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
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Hi")

        // Verify the URL contains streamGenerateContent (streaming path)
        let capturedURL = mockClient.capturedRequests.first?.url?.absoluteString ?? ""
        XCTAssertTrue(capturedURL.contains("streamGenerateContent"), "Antigravity should use streaming URL")
    }

    func testChatUsesNonStreamingPathForClaude() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        // Enqueue a non-streaming Claude Messages API response
        let responseJSON: [String: Any] = [
            "id": "msg-456",
            "type": "message",
            "role": "assistant",
            "model": "claude-sonnet-4-5-20250929",
            "content": [
                ["type": "text", "text": "Hello from Claude"]
            ],
            "usage": [
                "input_tokens": 10,
                "output_tokens": 5
            ]
        ] as [String: Any]

        mockClient.enqueue(.json(responseJSON))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chat(
            modelId: "claude-sonnet-4-5-20250929",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Hello from Claude")
        XCTAssertEqual(mockClient.requestCount, 1)

        // Verify the request body does NOT contain "stream":true
        let capturedRequest = mockClient.capturedRequests.first!
        let bodyData = capturedRequest.httpBody!
        let bodyJSON = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
        let streamValue = bodyJSON["stream"] as? Bool
        XCTAssertNotEqual(streamValue, true, "Non-streaming request should not have stream:true")

        // Verify Accept header is application/json, not text/event-stream
        let acceptHeader = capturedRequest.value(forHTTPHeaderField: "Accept")
        XCTAssertEqual(acceptHeader, "application/json", "Non-streaming request should accept JSON")
    }
}

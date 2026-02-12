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
        XCTAssertTrue(capturedURL.contains("daily-cloudcode-pa.googleapis.com"), "Antigravity should use daily base URL, not production")
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

    // MARK: - chatNonStream tests

    func testChatNonStreamDirectCall() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        let responseJSON: [String: Any] = [
            "id": "msg-789",
            "type": "message",
            "role": "assistant",
            "model": "claude-sonnet-4-5-20250929",
            "content": [
                ["type": "text", "text": "Direct non-stream response"]
            ],
            "usage": [
                "input_tokens": 8,
                "output_tokens": 4
            ]
        ] as [String: Any]

        mockClient.enqueue(.json(responseJSON))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chatNonStream(
            modelId: "claude-sonnet-4-5-20250929",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        XCTAssertEqual(response.fullText, "Direct non-stream response")
        XCTAssertEqual(mockClient.requestCount, 1)

        let capturedRequest = mockClient.capturedRequests.first!
        let acceptHeader = capturedRequest.value(forHTTPHeaderField: "Accept")
        XCTAssertEqual(acceptHeader, "application/json", "chatNonStream should use JSON accept header")
    }

    func testChatNonStreamThrowsForStreamOnlyProvider() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        do {
            _ = try await service.chatNonStream(
                modelId: "gemini-2.0-flash",
                messages: [LLMMessage(role: .user, content: [.text("hello")])]
            )
            XCTFail("Expected error for streaming-only provider")
        } catch let error as LLMServiceError {
            XCTAssertTrue(error.message.contains("does not support non-streaming"), "Error should mention non-streaming not supported, got: \(error.message)")
        } catch {
            XCTFail("Expected LLMServiceError, got \(type(of: error)): \(error)")
        }

        XCTAssertEqual(mockClient.requestCount, 0, "No HTTP request should be made for unsupported provider")
    }

    func testChatNonStreamRecordsTrace() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .geminiCLI,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .geminiCLI, metadata: ["project_id": "test-project"])

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(subsystem: "test", storageDirectory: storageDir)

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [["text": "Traced response"]],
                        "role": "model"
                    ]
                ]
            ],
            "responseId": "resp-trace",
            "modelVersion": "gemini-2.0-flash"
        ]
        mockClient.enqueue(.json(responseJSON))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chatNonStream(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )
        XCTAssertEqual(response.fullText, "Traced response")

        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain 1 trace entry")

        let entry = try XCTUnwrap(entries.first)
        let comment = try XCTUnwrap(entry["comment"] as? String)
        XCTAssertTrue(comment.contains("chatNonStream"), "Trace should record method as chatNonStream")

        let harResponse = try XCTUnwrap(entry["response"] as? [String: Any])
        let status = try XCTUnwrap(harResponse["status"] as? Int)
        XCTAssertEqual(status, 200)
    }

    func testChatNonStreamAPIError() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        mockClient.enqueue(.error(429, message: "Rate limit exceeded"))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        do {
            _ = try await service.chatNonStream(
                modelId: "claude-sonnet-4-5-20250929",
                messages: [LLMMessage(role: .user, content: [.text("hello")])]
            )
            XCTFail("Expected error")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertTrue(error.message.contains("Rate limit exceeded"))
        } catch {
            XCTFail("Expected LLMServiceError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - chatStream tests

    func testChatStreamYieldsChunks() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"chunk1 \"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"chunk2 \"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"chunk3\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
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

        var chunks: [LLMChatChunk] = []
        let stream = service.chatStream(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )
        for try await chunk in stream {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks.count, 3, "Should yield 3 chunks")
        XCTAssertEqual(chunks[0].delta, "chunk1 ")
        XCTAssertEqual(chunks[1].delta, "chunk2 ")
        XCTAssertEqual(chunks[2].delta, "chunk3")

        for chunk in chunks {
            if case .text = chunk.partType {} else {
                XCTFail("All chunks should be text type")
            }
        }
    }

    func testChatStreamClaudeSSE() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        let sseResponse = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-stream-1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-sonnet-4-5-20250929\",\"content\":[],\"usage\":{\"input_tokens\":10,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello \"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"from stream\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_delta",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}",
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

        var textDeltas: [String] = []
        let stream = service.chatStream(
            modelId: "claude-sonnet-4-5-20250929",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )
        for try await chunk in stream {
            if case .text = chunk.partType {
                textDeltas.append(chunk.delta)
            }
        }

        XCTAssertEqual(textDeltas.joined(), "Hello from stream")

        // Verify streaming URL was used
        let capturedURL = mockClient.capturedRequests.first?.url?.absoluteString ?? ""
        XCTAssertTrue(capturedURL.contains("anthropic.com"), "Should use Anthropic API")
        let capturedRequest = mockClient.capturedRequests.first!
        let acceptHeader = capturedRequest.value(forHTTPHeaderField: "Accept")
        XCTAssertEqual(acceptHeader, "text/event-stream", "chatStream should use SSE accept header")
    }

    func testChatStreamAPIError() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        mockClient.enqueue(.error(503, message: "Service unavailable"))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let stream = service.chatStream(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected error")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error.statusCode, 503)
            XCTAssertTrue(error.message.contains("Service unavailable"))
        } catch {
            XCTFail("Expected LLMServiceError, got \(type(of: error)): \(error)")
        }
    }

    func testChatStreamPreservesUnicode() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\\u041f\\u0440\\u0438\\u0432\\u0435\\u0442 \"}],\"role\":\"model\"}}]}",
            "",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\\u4e16\\u754c \\ud83c\\udf0d\"}],\"role\":\"model\"}}]}",
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

        var allText = ""
        let stream = service.chatStream(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )
        for try await chunk in stream {
            allText += chunk.delta
        }

        XCTAssertTrue(allText.contains("Привет"), "Stream should preserve Russian text")
        XCTAssertTrue(allText.contains("世界"), "Stream should preserve Chinese text")
        XCTAssertTrue(allText.contains("🌍"), "Stream should preserve emoji")
        XCTAssertFalse(allText.contains("\u{FFFD}"), "Stream should not contain replacement characters")
    }

    // MARK: - InlineData tests

    func testStreamAggregationWithInlineData() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        // Real minimal PNG header as base64
        let base64PNG = "iVBORw0KGgo="
        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Here is an image:\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"\(base64PNG)\"}}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
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
            messages: [LLMMessage(role: .user, content: [.text("generate image")])]
        )

        XCTAssertEqual(response.fullText, "Here is an image:")
        XCTAssertEqual(response.content.count, 2, "Should have text + inlineData parts")

        if case .text(let text) = response.content[0] {
            XCTAssertEqual(text, "Here is an image:")
        } else {
            XCTFail("First part should be text")
        }

        if case .inlineData(let data, let mimeType) = response.content[1] {
            XCTAssertEqual(mimeType, "image/png")
            XCTAssertFalse(data.isEmpty, "Decoded data should not be empty")
        } else {
            XCTFail("Second part should be inlineData")
        }
    }

    func testNonStreamingResponseWithInlineData() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .geminiCLI,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .geminiCLI, metadata: ["project_id": "test-project"])

        let base64PNG = "iVBORw0KGgo="
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "Generated:"],
                            ["inlineData": ["mimeType": "image/png", "data": base64PNG]]
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
            "responseId": "resp-img",
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
            messages: [LLMMessage(role: .user, content: [.text("generate image")])]
        )

        XCTAssertEqual(response.fullText, "Generated:")
        XCTAssertEqual(response.content.count, 2, "Should have text + inlineData parts")

        if case .inlineData(let data, let mimeType) = response.content[1] {
            XCTAssertEqual(mimeType, "image/png")
            XCTAssertFalse(data.isEmpty)
        } else {
            XCTFail("Second part should be inlineData")
        }
    }

    func testStreamInlineDataChunkEmittedCorrectly() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let base64PNG = "iVBORw0KGgo="
        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/jpeg\",\"data\":\"\(base64PNG)\"}}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
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

        var chunks: [LLMChatChunk] = []
        let stream = service.chatStream(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("image please")])]
        )
        for try await chunk in stream {
            chunks.append(chunk)
        }

        let inlineChunks = chunks.filter {
            if case .inlineData = $0.partType { return true }
            return false
        }
        XCTAssertEqual(inlineChunks.count, 1, "Should emit exactly one inlineData chunk")

        if case .inlineData(let mimeType) = inlineChunks.first?.partType {
            XCTAssertEqual(mimeType, "image/jpeg")
        }
        XCTAssertEqual(inlineChunks.first?.delta, base64PNG)
    }

    func testNonStreamingInlineDataWithSnakeCaseKeys() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .geminiCLI,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .geminiCLI, metadata: ["project_id": "test-project"])

        let base64PNG = "iVBORw0KGgo="
        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["inline_data": ["mime_type": "image/webp", "data": base64PNG]]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ],
            "responseId": "resp-snake",
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
            messages: [LLMMessage(role: .user, content: [.text("image")])]
        )

        XCTAssertEqual(response.content.count, 1)
        if case .inlineData(_, let mimeType) = response.content[0] {
            XCTAssertEqual(mimeType, "image/webp", "Should parse snake_case mime_type")
        } else {
            XCTFail("Expected inlineData part")
        }
    }

    func testNonStreamingInlineDataEmptyDataSkipped() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .geminiCLI,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .geminiCLI, metadata: ["project_id": "test-project"])

        let responseJSON: [String: Any] = [
            "candidates": [
                [
                    "content": [
                        "parts": [
                            ["text": "No image"],
                            ["inlineData": ["mimeType": "image/png", "data": ""]]
                        ],
                        "role": "model"
                    ],
                    "finishReason": "STOP"
                ]
            ],
            "responseId": "resp-empty",
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
            messages: [LLMMessage(role: .user, content: [.text("image")])]
        )

        XCTAssertEqual(response.content.count, 1, "Empty inlineData should be skipped")
        if case .text(let text) = response.content[0] {
            XCTAssertEqual(text, "No image")
        } else {
            XCTFail("Only text part should remain")
        }
    }

    // MARK: - Trace method consistency

    /// Helper: extract the trace method string from the first HAR entry's comment.
    /// HAR comment format: "TraceID: ...; Provider: ...; Account: ...; Method: {method}"
    private func extractTraceMethod(from service: LLMService) async throws -> String {
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain exactly 1 trace entry")
        let entry = try XCTUnwrap(entries.first)
        let comment = try XCTUnwrap(entry["comment"] as? String)
        // Parse "Method: xxx" from the comment
        let prefix = "Method: "
        guard let range = comment.range(of: prefix) else {
            XCTFail("Comment should contain 'Method: ' prefix, got: \(comment)")
            return ""
        }
        return String(comment[range.upperBound...])
    }

    private func makeTracingService(
        provider: LLMProvider,
        mockClient: MockHTTPClient
    ) -> (LLMService, URL) {
        let session = MockAccountSession(provider: provider, credentials: LLMCredentials(accessToken: "test-token"))
        if provider != .claudeCode {
            session.info = LLMAccountInfo(provider: provider, metadata: ["project_id": "test-project"])
        }
        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        let config = LLMLoggingConfig(subsystem: "test", storageDirectory: storageDir)
        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )
        return (service, storageDir)
    }

    func testChatRecordsMethodAsChatForNonStreamProvider() async throws {
        let mockClient = MockHTTPClient()
        let (service, storageDir) = makeTracingService(provider: .geminiCLI, mockClient: mockClient)
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let responseJSON: [String: Any] = [
            "candidates": [[
                "content": ["parts": [["text": "ok"]], "role": "model"]
            ]],
            "responseId": "r1",
            "modelVersion": "gemini-2.0-flash"
        ]
        mockClient.enqueue(.json(responseJSON))

        _ = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hi")])]
        )

        let method = try await extractTraceMethod(from: service)
        XCTAssertEqual(method, "chat", "chat() via non-stream path should record method as 'chat'")
    }

    func testChatRecordsMethodAsChatForStreamFallback() async throws {
        let mockClient = MockHTTPClient()
        let (service, storageDir) = makeTracingService(provider: .antigravity, mockClient: mockClient)
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")
        mockClient.enqueue(.sse(sseResponse))

        _ = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hi")])]
        )

        let method = try await extractTraceMethod(from: service)
        XCTAssertEqual(method, "chat", "chat() via stream fallback should record method as 'chat'")
    }

    func testChatNonStreamRecordsMethodAsChatNonStream() async throws {
        let mockClient = MockHTTPClient()
        let (service, storageDir) = makeTracingService(provider: .claudeCode, mockClient: mockClient)
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let responseJSON: [String: Any] = [
            "id": "msg-1", "type": "message", "role": "assistant",
            "model": "claude-sonnet-4-5-20250929",
            "content": [["type": "text", "text": "ok"]],
            "usage": ["input_tokens": 1, "output_tokens": 1]
        ] as [String: Any]
        mockClient.enqueue(.json(responseJSON))

        _ = try await service.chatNonStream(
            modelId: "claude-sonnet-4-5-20250929",
            messages: [LLMMessage(role: .user, content: [.text("hi")])]
        )

        let method = try await extractTraceMethod(from: service)
        XCTAssertEqual(method, "chatNonStream", "chatNonStream() should record method as 'chatNonStream'")
    }

    func testChatStreamRecordsMethodAsChatStream() async throws {
        let mockClient = MockHTTPClient()
        let (service, storageDir) = makeTracingService(provider: .antigravity, mockClient: mockClient)
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")
        mockClient.enqueue(.sse(sseResponse))

        let stream = service.chatStream(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hi")])]
        )
        for try await _ in stream {}

        let method = try await extractTraceMethod(from: service)
        XCTAssertEqual(method, "chatStream", "chatStream() should record method as 'chatStream'")
    }
}

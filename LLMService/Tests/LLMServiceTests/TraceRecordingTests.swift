import XCTest
@testable import LLMService

final class TraceRecordingTests: XCTestCase {

    // MARK: - Trace recorded on successful stream

    func testChatStreamRecordsTraceOnSuccess() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(
            subsystem: "test",
            storageDirectory: storageDir
        )

        // Claude now uses non-streaming path — enqueue a non-streaming JSON response
        let responseJSON: [String: Any] = [
            "id": "msg-1",
            "type": "message",
            "role": "assistant",
            "model": "claude-3",
            "content": [
                ["type": "text", "text": "Hi"]
            ],
            "usage": [
                "input_tokens": 5,
                "output_tokens": 1
            ]
        ] as [String: Any]

        mockClient.enqueue(.json(responseJSON))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chat(
            modelId: "claude-3",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )
        XCTAssertEqual(response.fullText, "Hi")

        // Verify HAR export contains the trace
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain 1 trace entry")

        let entry = try XCTUnwrap(entries.first)
        let request = try XCTUnwrap(entry["request"] as? [String: Any])
        XCTAssertEqual(request["url"] as? String, "https://api.anthropic.com/v1/messages")
    }

    // MARK: - Trace recorded on API error

    func testChatStreamRecordsTraceOnError() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(
            subsystem: "test",
            storageDirectory: storageDir
        )

        // Enqueue a 500 error response
        mockClient.enqueue(.error(500, message: "Internal server error"))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        do {
            _ = try await service.chat(
                modelId: "claude-3",
                messages: [LLMMessage(role: .user, content: [.text("hello")])]
            )
            XCTFail("Expected error")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("Expected LLMServiceError, got \(type(of: error))")
        }

        // Verify HAR export contains the error trace
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain 1 error trace entry")

        let entry = try XCTUnwrap(entries.first)
        let comment = try XCTUnwrap(entry["comment"] as? String)
        XCTAssertTrue(comment.contains("chat"), "Trace should record method as chat")
    }

    // MARK: - HAR response body contains raw SSE lines

    func testHARResponseBodyContainsRawSSELines() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(
            subsystem: "test",
            storageDirectory: storageDir
        )

        let sseLines = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello world\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: [DONE]",
            "",
        ]
        let sseResponse = sseLines.joined(separator: "\n")
        mockClient.enqueue(.sse(sseResponse))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )
        XCTAssertEqual(response.fullText, "Hello world")

        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.first)
        let harResponse = try XCTUnwrap(entry["response"] as? [String: Any])
        let content = try XCTUnwrap(harResponse["content"] as? [String: Any])
        let body = try XCTUnwrap(content["text"] as? String)

        // Body must contain raw SSE lines, not just extracted text
        XCTAssertTrue(body.contains("candidates"), "HAR body should contain raw SSE data JSON")
        XCTAssertFalse(body == "Hello world", "HAR body must not be just the extracted text")
    }

    // MARK: - HAR response mimeType is text/event-stream for streaming

    func testHARResponseMimeTypeIsEventStreamForStreaming() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(
            subsystem: "test",
            storageDirectory: storageDir
        )

        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}",
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")

        mockClient.enqueue(.sse(sseResponse))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        _ = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.first)
        let harResponse = try XCTUnwrap(entry["response"] as? [String: Any])
        let content = try XCTUnwrap(harResponse["content"] as? [String: Any])
        let mimeType = try XCTUnwrap(content["mimeType"] as? String)

        XCTAssertEqual(mimeType, "text/event-stream", "Streaming response should have text/event-stream mimeType")
    }

    // MARK: - HAR response body respects size cap

    func testHARResponseBodyRespectsSizeCap() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(
            subsystem: "test",
            storageDirectory: storageDir
        )

        // Build an SSE response that exceeds 512KB of raw lines
        var sseLines: [String] = []

        // Add many data events to exceed 512KB
        let longText = String(repeating: "x", count: 1000)
        for _ in 0..<600 {
            sseLines.append("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\(longText)\"}],\"role\":\"model\"}}],\"modelVersion\":\"gemini-2.0-flash\"}")
            sseLines.append("")
        }

        sseLines.append(contentsOf: [
            "data: [DONE]",
            "",
        ])

        let sseResponse = sseLines.joined(separator: "\n")
        mockClient.enqueue(.sse(sseResponse))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        _ = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.first)
        let harResponse = try XCTUnwrap(entry["response"] as? [String: Any])
        let content = try XCTUnwrap(harResponse["content"] as? [String: Any])
        let body = try XCTUnwrap(content["text"] as? String)

        let capBytes = 512 * 1024
        XCTAssertLessThanOrEqual(body.utf8.count, capBytes + 2048,
            "HAR response body should be approximately bounded by the 512KB cap (with tolerance for the last segment)")
        XCTAssertGreaterThan(body.utf8.count, 0, "HAR response body should not be empty")
    }

    // MARK: - Unicode preservation in streaming and HAR

    func testUnicodePreservedInStreamingAndHAR() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(subsystem: "test", storageDirectory: storageDir)

        let sseResponse = [
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\\u041f\\u0440\\u0438\\u0432\\u0435\\u0442 \\u043c\\u0438\\u0440 \"}],\"role\":\"model\"}}]}",
            "",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"\\u4f60\\u597d\\u4e16\\u754c \"}],\"role\":\"model\"}}]}",
            "",
            "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello \\ud83c\\udf0d\"}],\"role\":\"model\"}}]}",
            "",
            "data: [DONE]",
            "",
        ].joined(separator: "\n")

        mockClient.enqueue(.sse(sseResponse))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        // Verify unicode preserved in response text
        XCTAssertTrue(response.fullText.contains("Привет мир"), "Response should contain Russian text")
        XCTAssertTrue(response.fullText.contains("你好世界"), "Response should contain Chinese text")
        XCTAssertFalse(response.fullText.contains("\u{FFFD}"), "Response should not contain replacement characters")

        // Verify HAR body preserves unicode in raw SSE data
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.first)
        let harResponse = try XCTUnwrap(entry["response"] as? [String: Any])
        let content = try XCTUnwrap(harResponse["content"] as? [String: Any])
        let body = try XCTUnwrap(content["text"] as? String)

        XCTAssertFalse(body.isEmpty, "HAR body should not be empty")
        XCTAssertFalse(body.contains("\u{FFFD}"), "HAR body should not contain replacement characters")
    }

    // MARK: - HAR export with no storage directory returns empty

    func testExportHARWithNoStorageReturnsEmptyEntries() async throws {
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        let config = LLMLoggingConfig(subsystem: "test", storageDirectory: nil)

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: MockHTTPClient(),
            oauthLauncher: MockOAuthLauncher()
        )

        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 0)
    }

    // MARK: - Trace recorded on network failure (non-streaming)

    func testTraceRecordedOnNetworkFailure() async throws {
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

        // Enqueue a network error (timeout)
        mockClient.enqueueError(URLError(.timedOut))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        do {
            _ = try await service.chat(
                modelId: "gemini-2.0-flash",
                messages: [LLMMessage(role: .user, content: [.text("hello")])]
            )
            XCTFail("Expected error")
        } catch {
            // Expected
        }

        // Verify HAR contains 1 entry with error field populated
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain 1 trace entry for network failure")

        let entry = try XCTUnwrap(entries.first)
        let comment = try XCTUnwrap(entry["comment"] as? String)
        XCTAssertTrue(comment.contains("chat"), "Trace method should be chat")
    }

    // MARK: - Trace recorded on stream network failure

    func testTraceRecordedOnStreamNetworkFailure() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .antigravity,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info = LLMAccountInfo(provider: .antigravity, metadata: ["project_id": "test-project"])

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(subsystem: "test", storageDirectory: storageDir)

        // Enqueue a network error (not connected to internet)
        mockClient.enqueueError(URLError(.notConnectedToInternet))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let stream = service.chatStream(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        do {
            for try await _ in stream {
                // Consume stream
            }
            XCTFail("Expected error")
        } catch {
            // Expected
        }

        // Verify HAR contains 1 entry with error
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain 1 trace entry for stream network failure")
    }

    // MARK: - Non-streaming chat records trace on success

    func testNonStreamingChatRecordsTraceOnSuccess() async throws {
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
                        "parts": [["text": "Hello"]],
                        "role": "model"
                    ]
                ]
            ],
            "responseId": "resp-1",
            "modelVersion": "gemini-2.0-flash"
        ]
        mockClient.enqueue(.json(responseJSON))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        let response = try await service.chat(
            modelId: "gemini-2.0-flash",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )
        XCTAssertEqual(response.fullText, "Hello")

        // Verify HAR contains 1 entry with method "chat", isStreaming false
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain 1 trace entry")

        let entry = try XCTUnwrap(entries.first)
        let comment = try XCTUnwrap(entry["comment"] as? String)
        XCTAssertTrue(comment.contains("chat"), "Trace should record method as chat")

        // Verify response was recorded
        let harResponse = try XCTUnwrap(entry["response"] as? [String: Any])
        let status = try XCTUnwrap(harResponse["status"] as? Int)
        XCTAssertEqual(status, 200)
    }

    // MARK: - Non-streaming chat records trace on API error

    func testNonStreamingChatRecordsTraceOnAPIError() async throws {
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

        // Enqueue 500 error via data() path (non-streaming)
        mockClient.enqueue(.error(500, message: "Internal server error"))

        let service = LLMService(
            session: session,
            loggingConfig: config,
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        do {
            _ = try await service.chat(
                modelId: "gemini-2.0-flash",
                messages: [LLMMessage(role: .user, content: [.text("hello")])]
            )
            XCTFail("Expected error")
        } catch let error as LLMServiceError {
            XCTAssertEqual(error.statusCode, 500)
        } catch {
            XCTFail("Expected LLMServiceError, got \(type(of: error))")
        }

        // Verify HAR error trace recorded
        let harData = try await service.exportHAR(lastMinutes: 5)
        let har = try XCTUnwrap(JSONSerialization.jsonObject(with: harData) as? [String: Any])
        let log = try XCTUnwrap(har["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "HAR should contain 1 error trace entry")

        let entry = try XCTUnwrap(entries.first)
        let comment = try XCTUnwrap(entry["comment"] as? String)
        XCTAssertTrue(comment.contains("chat"), "Trace should record method as chat")
    }
}

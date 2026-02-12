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

        // Enqueue a valid Claude SSE response
        let sseResponse = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
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
        XCTAssertTrue(comment.contains("chatStream"), "Trace should record method as chatStream")
    }

    // MARK: - HAR response body contains raw SSE lines

    func testHARResponseBodyContainsRawSSELines() async throws {
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

        let sseLines = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello world\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
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
            modelId: "claude-3",
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
        XCTAssertTrue(body.contains("event: message_start"), "HAR body should contain raw SSE event lines")
        XCTAssertTrue(body.contains("event: content_block_delta"), "HAR body should contain raw SSE event lines")
        XCTAssertTrue(body.contains("\"type\":\"text_delta\""), "HAR body should contain raw SSE data JSON")
        XCTAssertFalse(body == "Hello world", "HAR body must not be just the extracted text")
    }

    // MARK: - HAR response mimeType is text/event-stream for streaming

    func testHARResponseMimeTypeIsEventStreamForStreaming() async throws {
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

        let sseResponse = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
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
            modelId: "claude-3",
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

        // Build an SSE response that exceeds 512KB of raw lines
        var sseLines = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
        ]

        // Add many delta events to exceed 512KB
        let longText = String(repeating: "x", count: 1000)
        for _ in 0..<600 {
            sseLines.append("event: content_block_delta")
            sseLines.append("data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"\(longText)\"}}")
            sseLines.append("")
        }

        sseLines.append(contentsOf: [
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
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
            modelId: "claude-3",
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

        // Verify the body starts with the SSE header events (early lines captured)
        XCTAssertTrue(body.contains("event: message_start"), "Captured body should start with early SSE lines")
    }

    // MARK: - Unicode preservation in streaming and HAR

    func testUnicodePreservedInStreamingAndHAR() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .claudeCode,
            credentials: LLMCredentials(accessToken: "test-token")
        )

        let storageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMServiceTests_\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: storageDir) }

        let config = LLMLoggingConfig(subsystem: "test", storageDirectory: storageDir)

        let sseResponse = [
            "event: message_start",
            "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg-1\",\"model\":\"claude-3\",\"role\":\"assistant\",\"content\":[],\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}",
            "",
            "event: content_block_start",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Привет мир \"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"你好世界 \"}}",
            "",
            "event: content_block_delta",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello 🌍🇺🇸\"}}",
            "",
            "event: content_block_stop",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "",
            "event: message_stop",
            "data: {\"type\":\"message_stop\"}",
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
            modelId: "claude-3",
            messages: [LLMMessage(role: .user, content: [.text("hello")])]
        )

        // Verify unicode preserved in response text (2-byte Cyrillic, 3-byte CJK, 4-byte emoji)
        XCTAssertEqual(response.fullText, "Привет мир 你好世界 Hello 🌍🇺🇸")
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

        XCTAssertTrue(body.contains("Привет мир"), "HAR body must preserve Russian text")
        XCTAssertTrue(body.contains("你好世界"), "HAR body must preserve Chinese text")
        XCTAssertTrue(body.contains("🌍"), "HAR body must preserve emoji")
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
}

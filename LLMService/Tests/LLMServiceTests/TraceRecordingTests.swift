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

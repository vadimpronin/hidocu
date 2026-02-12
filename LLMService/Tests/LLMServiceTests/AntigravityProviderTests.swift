import XCTest
@testable import LLMService

final class AntigravityProviderTests: XCTestCase {

    private let testCredentials = LLMCredentials(accessToken: "test-token")

    // MARK: - URL

    func testStreamRequestURL() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        // Fix #1: Must use daily-cloudcode-pa.googleapis.com (not cloudcode-pa.googleapis.com)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
            "Antigravity streaming URL must use daily-cloudcode-pa.googleapis.com domain"
        )

        // Ensure it does NOT use the non-daily domain
        XCTAssertFalse(
            request.url?.absoluteString.contains("https://cloudcode-pa.googleapis.com") == true,
            "Must NOT use cloudcode-pa.googleapis.com without daily- prefix"
        )
    }

    // MARK: - Headers

    func testStreamRequestContainsRequiredHeaders() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        // Fix #2: Required headers for Antigravity streaming
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "antigravity/1.104.0 darwin/arm64")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "text/event-stream",
            "Antigravity streaming requests must include Accept: text/event-stream header"
        )
    }

    func testStreamRequestDoesNotContainGeminiSpecificHeaders() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        // Fix #2: These headers are Gemini-only and must NOT be present in Antigravity
        XCTAssertNil(
            request.value(forHTTPHeaderField: "X-Goog-Api-Client"),
            "Antigravity must NOT include X-Goog-Api-Client header (Gemini-only)"
        )
        XCTAssertNil(
            request.value(forHTTPHeaderField: "Client-Metadata"),
            "Antigravity must NOT include Client-Metadata header (Gemini-only)"
        )
    }

    func testStreamRequestUserAgentDiffersFromGemini() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityUA = antigravityRequest.value(forHTTPHeaderField: "User-Agent")
        let geminiUA = geminiRequest.value(forHTTPHeaderField: "User-Agent")

        XCTAssertEqual(antigravityUA, "antigravity/1.104.0 darwin/arm64")
        XCTAssertEqual(geminiUA, "google-api-nodejs-client/9.15.1")
        XCTAssertNotEqual(
            antigravityUA,
            geminiUA,
            "Antigravity and Gemini must have different User-Agent strings"
        )
    }

    func testStreamRequestAcceptHeaderDiffersFromGeminiNonStream() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildNonStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityAccept = antigravityRequest.value(forHTTPHeaderField: "Accept")
        let geminiAccept = geminiRequest.value(forHTTPHeaderField: "Accept")

        XCTAssertEqual(
            antigravityAccept,
            "text/event-stream",
            "Antigravity streaming must use text/event-stream"
        )
        XCTAssertNotEqual(
            geminiAccept,
            "text/event-stream",
            "Gemini non-streaming should not use text/event-stream"
        )
    }

    // MARK: - Request Body (Antigravity Envelope)

    func testRequestContainsAntigravityEnvelope() throws {
        let provider = AntigravityProvider(projectId: "test-project")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)

        // Verify all envelope fields are present
        XCTAssertNotNil(body["model"], "Envelope must contain 'model' field")
        XCTAssertNotNil(body["userAgent"], "Envelope must contain 'userAgent' field")
        XCTAssertNotNil(body["requestType"], "Envelope must contain 'requestType' field")
        XCTAssertNotNil(body["project"], "Envelope must contain 'project' field")
        XCTAssertNotNil(body["requestId"], "Envelope must contain 'requestId' field")
        XCTAssertNotNil(body["request"], "Envelope must contain nested 'request' field")

        // Verify envelope values
        XCTAssertEqual(body["userAgent"] as? String, "antigravity")
        XCTAssertEqual(body["requestType"] as? String, "agent")

        let requestId = try XCTUnwrap(body["requestId"] as? String)
        XCTAssertTrue(
            requestId.hasPrefix("agent-"),
            "requestId must start with 'agent-' prefix"
        )
    }

    func testRequestContainsProjectField() throws {
        let provider = AntigravityProvider(projectId: "my-project-789")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        XCTAssertEqual(
            body["project"] as? String,
            "my-project-789",
            "Envelope 'project' field must match projectId passed to provider"
        )
    }

    func testRequestContainsModelField() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-flash-thinking",
            messages: [LLMMessage(role: .user, content: [.text("test")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        XCTAssertEqual(
            body["model"] as? String,
            "gemini-2.5-flash-thinking",
            "Envelope 'model' field must match modelId passed to buildStreamRequest"
        )
    }

    func testRequestContainsNestedRequestWithContents() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let nestedRequest = try XCTUnwrap(
            body["request"] as? [String: Any],
            "Envelope must contain nested 'request' dictionary"
        )

        let contents = try XCTUnwrap(
            nestedRequest["contents"] as? [[String: Any]],
            "Nested request must contain 'contents' array"
        )

        XCTAssertFalse(contents.isEmpty, "Contents array must not be empty")
    }

    func testRequestContainsSessionId() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let nestedRequest = try XCTUnwrap(body["request"] as? [String: Any])
        let sessionId = try XCTUnwrap(
            nestedRequest["sessionId"] as? String,
            "Nested request must contain 'sessionId' field"
        )

        XCTAssertTrue(
            sessionId.hasPrefix("-"),
            "sessionId must start with '-' prefix"
        )
    }

    func testRequestDoesNotContainSafetySettings() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let nestedRequest = try XCTUnwrap(body["request"] as? [String: Any])

        XCTAssertNil(
            nestedRequest["safetySettings"],
            "Antigravity requests must NOT include safetySettings (Gemini-only feature)"
        )
    }

    // MARK: - Non-Streaming

    func testNonStreamRequestThrows() throws {
        let provider = AntigravityProvider(projectId: "proj")

        XCTAssertThrowsError(
            try provider.buildNonStreamRequest(
                modelId: "gemini-2.5-pro",
                messages: [LLMMessage(role: .user, content: [.text("hello")])],
                thinking: nil,
                credentials: testCredentials,
                traceId: "test"
            ),
            "buildNonStreamRequest must throw since Antigravity is streaming-only"
        ) { error in
            guard let serviceError = error as? LLMServiceError else {
                XCTFail("Expected LLMServiceError, got \(type(of: error))")
                return
            }
            XCTAssertTrue(
                serviceError.message.contains("non-streaming"),
                "Error message should mention non-streaming is not supported"
            )
        }
    }

    func testSupportsNonStreamingIsFalse() {
        let provider = AntigravityProvider(projectId: "proj")
        XCTAssertFalse(
            provider.supportsNonStreaming,
            "Antigravity is streaming-only, supportsNonStreaming must be false"
        )
    }

    // MARK: - Comparison with Gemini (Regression Tests)

    func testAntigravityAndGeminiUseDifferentDomains() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityURL = try XCTUnwrap(antigravityRequest.url?.absoluteString)
        let geminiURL = try XCTUnwrap(geminiRequest.url?.absoluteString)

        XCTAssertTrue(
            antigravityURL.contains("daily-cloudcode-pa.googleapis.com"),
            "Antigravity must use daily-cloudcode-pa.googleapis.com"
        )
        XCTAssertTrue(
            geminiURL.contains("cloudcode-pa.googleapis.com"),
            "Gemini uses cloudcode-pa.googleapis.com"
        )
        XCTAssertFalse(
            geminiURL.contains("daily-cloudcode-pa.googleapis.com"),
            "Gemini must NOT use daily- prefix"
        )
    }

    func testAntigravityAndGeminiEnvelopesAreDifferent() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityBody = try parseBody(antigravityRequest)
        let geminiBody = try parseBody(geminiRequest)

        // Antigravity has additional envelope fields
        XCTAssertNotNil(antigravityBody["userAgent"])
        XCTAssertNotNil(antigravityBody["requestType"])
        XCTAssertNotNil(antigravityBody["requestId"])

        let antigravityNestedRequest = antigravityBody["request"] as? [String: Any]
        let geminiNestedRequest = geminiBody["request"] as? [String: Any]

        // Antigravity has sessionId
        XCTAssertNotNil(antigravityNestedRequest?["sessionId"])

        // Gemini has safetySettings, Antigravity does not
        XCTAssertNotNil(geminiNestedRequest?["safetySettings"])
        XCTAssertNil(antigravityNestedRequest?["safetySettings"])
    }

    // MARK: - HTTP Method and Timeout

    func testStreamRequestUsesPostMethod() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testStreamRequestHasTimeout() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        XCTAssertEqual(request.timeoutInterval, 600, "Timeout must be 600 seconds")
    }

    // MARK: - Helpers

    private func parseBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

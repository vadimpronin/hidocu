import XCTest
@testable import LLMService

final class GeminiCLIProviderTests: XCTestCase {

    private let testCredentials = LLMCredentials(accessToken: "test-token")

    // MARK: - Project Field

    func testStreamRequestContainsProjectField() throws {
        let provider = GeminiCLIProvider(projectId: "my-project-123")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        XCTAssertEqual(body["project"] as? String, "my-project-123")
    }

    func testNonStreamRequestContainsProjectField() throws {
        let provider = GeminiCLIProvider(projectId: "my-project-456")
        let request = try provider.buildNonStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        XCTAssertEqual(body["project"] as? String, "my-project-456")
    }

    func testRequestContainsModelField() throws {
        let provider = GeminiCLIProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-flash",
            messages: [LLMMessage(role: .user, content: [.text("hi")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        XCTAssertEqual(body["model"] as? String, "gemini-2.5-flash")
    }

    func testRequestContainsNestedRequestField() throws {
        let provider = GeminiCLIProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let innerRequest = body["request"] as? [String: Any]
        XCTAssertNotNil(innerRequest, "Request body must contain nested 'request' field")
        let contents = innerRequest?["contents"] as? [[String: Any]]
        XCTAssertNotNil(contents, "Inner request must contain 'contents'")
    }

    // MARK: - Headers

    func testStreamRequestContainsRequiredHeaders() throws {
        let provider = GeminiCLIProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "google-api-nodejs-client/9.15.1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Goog-Api-Client"), "gl-node/22.17.0")
        XCTAssertTrue(
            request.value(forHTTPHeaderField: "Client-Metadata")?.contains("pluginType=GEMINI") == true,
            "Client-Metadata header must contain pluginType=GEMINI"
        )
    }

    // MARK: - URL

    func testStreamRequestURL() throws {
        let provider = GeminiCLIProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse"
        )
    }

    func testNonStreamRequestURL() throws {
        let provider = GeminiCLIProvider(projectId: "proj")
        let request = try provider.buildNonStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        XCTAssertEqual(
            request.url?.absoluteString,
            "https://cloudcode-pa.googleapis.com/v1internal:generateContent"
        )
    }

    // MARK: - Helpers

    private func parseBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

import XCTest
@testable import LLMService

final class AuthFlowTests: XCTestCase {
    func testLoginCallsSave() async throws {
        let mockClient = MockHTTPClient()
        let mockLauncher = MockOAuthLauncher()
        let session = MockAccountSession(provider: .claudeCode)

        // Set up callback URL with auth code (state must match the UUID generated in OAuthCoordinator)
        // The mock launcher captures the auth URL, and we set up a callback that echoes the state
        mockLauncher.echoStateInCallback = true

        // Enqueue token exchange response
        mockClient.enqueue(.json([
            "access_token": "new-access-token",
            "refresh_token": "new-refresh-token",
            "expires_in": 3600,
            "token_type": "bearer",
            "account": ["email_address": "test@example.com", "uuid": "acc-123"],
            "organization": ["uuid": "org-123", "name": "Test Org"]
        ]))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: mockLauncher
        )

        try await service.login()

        // Verify save was called
        XCTAssertEqual(session.saveCallCount, 1)
        XCTAssertEqual(session.savedCredentials?.accessToken, "new-access-token")
        XCTAssertEqual(session.savedCredentials?.refreshToken, "new-refresh-token")
    }

    func testGeminiRedirectURI() {
        let redirectURI = GeminiAuthProvider.redirectURI
        XCTAssertEqual(redirectURI, "http://localhost:8085/oauth2callback")
    }

    func testAntigravityRedirectURI() {
        let redirectURI = AntigravityAuthProvider.redirectURI
        XCTAssertEqual(redirectURI, "http://localhost:51121/oauth-callback")
    }

    func testLoginRejectsStateMismatch() async {
        let mockClient = MockHTTPClient()
        let mockLauncher = MockOAuthLauncher()
        let session = MockAccountSession(provider: .claudeCode)

        // Return a callback with a hardcoded wrong state
        mockLauncher.callbackURL = URL(string: "llmservice://auth/callback?code=test-code&state=wrong-state")!

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: mockLauncher
        )

        do {
            try await service.login()
            XCTFail("Expected state mismatch error")
        } catch {
            XCTAssertTrue("\(error)".contains("state mismatch"), "Expected CSRF error, got: \(error)")
        }
    }

    func testFetchProjectIDUsesCorrectIdeTypeForGemini() async throws {
        let mockClient = MockHTTPClient()

        // Enqueue loadCodeAssist response
        mockClient.enqueue(.json([
            "cloudaicompanionProject": "gemini-proj-123"
        ]))

        let projectId = try await GeminiAuthProvider.fetchProjectID(
            accessToken: "test-token",
            httpClient: mockClient
        )

        XCTAssertEqual(projectId, "gemini-proj-123")

        // Verify the request body contains IDE_UNSPECIFIED for GeminiCLI
        let request = try XCTUnwrap(mockClient.capturedRequests.first)
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(body["metadata"] as? [String: String])
        XCTAssertEqual(metadata["ideType"], "IDE_UNSPECIFIED")
    }

    func testFetchProjectIDUsesCorrectIdeTypeForAntigravity() async throws {
        let mockClient = MockHTTPClient()

        // Enqueue loadCodeAssist response
        mockClient.enqueue(.json([
            "cloudaicompanionProject": "ag-proj-456"
        ]))

        let projectId = try await AntigravityAuthProvider.fetchProjectID(
            accessToken: "test-token",
            httpClient: mockClient
        )

        XCTAssertEqual(projectId, "ag-proj-456")

        // Verify the request body contains ANTIGRAVITY for Antigravity
        let request = try XCTUnwrap(mockClient.capturedRequests.first)
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(body["metadata"] as? [String: String])
        XCTAssertEqual(metadata["ideType"], "ANTIGRAVITY")
    }

    func testFetchProjectIDCallsLoadCodeAssistEndpoint() async throws {
        let mockClient = MockHTTPClient()
        mockClient.enqueue(.json(["cloudaicompanionProject": "proj"]))

        _ = try await GeminiAuthProvider.fetchProjectID(
            accessToken: "my-token",
            httpClient: mockClient
        )

        let request = try XCTUnwrap(mockClient.capturedRequests.first)
        XCTAssertEqual(request.url?.host, "cloudcode-pa.googleapis.com")
        XCTAssertTrue(request.url?.path.contains("loadCodeAssist") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-token")
    }

    func testResolveProviderPassesProjectIdToGeminiCLI() async throws {
        let mockClient = MockHTTPClient()
        let session = MockAccountSession(
            provider: .geminiCLI,
            credentials: LLMCredentials(accessToken: "test-token")
        )
        session.info.metadata["project_id"] = "my-gemini-project"

        // Enqueue a 500 error (we just want to inspect the request, not get a valid response)
        mockClient.enqueue(.error(500, message: "test"))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient,
            oauthLauncher: MockOAuthLauncher()
        )

        // Call chatStream and consume the expected error
        let stream = service.chatStream(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hi")])]
        )
        do {
            for try await _ in stream {}
        } catch {
            // Expected 500 error — we only need to inspect the request
        }

        // Verify the captured request contains the project field
        let request = try XCTUnwrap(mockClient.capturedRequests.first)
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["project"] as? String, "my-gemini-project")
    }

    func testBuildAuthURLContainsCorrectRedirectURI() {
        let redirectURI = GeminiAuthProvider.redirectURI
        let authURL = GeminiAuthProvider.buildAuthURL(
            state: "test-state",
            redirectURI: redirectURI
        )

        guard let components = URLComponents(url: authURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            XCTFail("Failed to parse auth URL")
            return
        }

        let redirectURIParam = queryItems.first(where: { $0.name == "redirect_uri" })?.value
        XCTAssertEqual(redirectURIParam, "http://localhost:8085/oauth2callback")
    }
}

import XCTest
@testable import LLMService

final class AuthFlowTests: XCTestCase {

    // MARK: - Redirect URI constants

    func testClaudeRedirectURI() {
        XCTAssertEqual(ClaudeCodeAuthProvider.redirectURI, "http://localhost:54545/callback")
    }

    func testGeminiRedirectURI() {
        let redirectURI = GeminiAuthProvider.redirectURI
        XCTAssertEqual(redirectURI, "http://localhost:8085/oauth2callback")
    }

    func testAntigravityRedirectURI() {
        let redirectURI = AntigravityAuthProvider.redirectURI
        XCTAssertEqual(redirectURI, "http://localhost:51121/oauth-callback")
    }

    // MARK: - Claude auth URL building

    func testClaudeBuildAuthURLContainsCorrectRedirectURI() throws {
        let pkceCodes = try PKCEGenerator.generate()
        let redirectURI = ClaudeCodeAuthProvider.redirectURI
        let authURL = ClaudeCodeAuthProvider.buildAuthURL(
            pkceCodes: pkceCodes,
            state: "test-state",
            redirectURI: redirectURI
        )

        let components = try XCTUnwrap(URLComponents(url: authURL, resolvingAgainstBaseURL: false))
        let queryItems = try XCTUnwrap(components.queryItems)

        let redirectParam = queryItems.first(where: { $0.name == "redirect_uri" })?.value
        XCTAssertEqual(redirectParam, "http://localhost:54545/callback")

        let codeChallenge = queryItems.first(where: { $0.name == "code_challenge" })?.value
        XCTAssertEqual(codeChallenge, pkceCodes.codeChallenge)

        let challengeMethod = queryItems.first(where: { $0.name == "code_challenge_method" })?.value
        XCTAssertEqual(challengeMethod, "S256")

        let stateParam = queryItems.first(where: { $0.name == "state" })?.value
        XCTAssertEqual(stateParam, "test-state")

        let responseType = queryItems.first(where: { $0.name == "response_type" })?.value
        XCTAssertEqual(responseType, "code")
    }

    // MARK: - Claude token exchange

    func testClaudeTokenExchangeParsesResponse() async throws {
        let mockClient = MockHTTPClient()
        let pkceCodes = try PKCEGenerator.generate()

        mockClient.enqueue(.json([
            "access_token": "new-access-token",
            "refresh_token": "new-refresh-token",
            "expires_in": 3600,
            "token_type": "bearer",
            "account": ["email_address": "test@example.com", "uuid": "acc-123"],
            "organization": ["uuid": "org-123", "name": "Test Org"]
        ]))

        let (credentials, email) = try await ClaudeCodeAuthProvider.exchangeCodeForTokens(
            code: "test-code",
            state: "test-state",
            pkceCodes: pkceCodes,
            redirectURI: ClaudeCodeAuthProvider.redirectURI,
            httpClient: mockClient
        )

        XCTAssertEqual(credentials.accessToken, "new-access-token")
        XCTAssertEqual(credentials.refreshToken, "new-refresh-token")
        XCTAssertNotNil(credentials.expiresAt)
        XCTAssertEqual(email, "test@example.com")

        // Verify the request body contains correct redirect_uri
        let request = try XCTUnwrap(mockClient.capturedRequests.first)
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["redirect_uri"] as? String, "http://localhost:54545/callback")
        XCTAssertEqual(body["grant_type"] as? String, "authorization_code")
    }

    // MARK: - State validation (CSRF protection)

    func testExtractCodeRejectsStateMismatch() {
        let url = URL(string: "http://localhost:54545/callback?code=test-code&state=wrong-state")!
        XCTAssertThrowsError(try OAuthCoordinator.extractCode(from: url, expectedState: "expected-state")) { error in
            XCTAssertTrue("\(error)".contains("state mismatch"), "Expected CSRF error, got: \(error)")
        }
    }

    func testExtractCodeAcceptsMatchingState() throws {
        let state = "my-state-123"
        let url = URL(string: "http://localhost:54545/callback?code=test-code&state=\(state)")!
        let code = try OAuthCoordinator.extractCode(from: url, expectedState: state)
        XCTAssertEqual(code, "test-code")
    }

    func testExtractCodeRejectsMissingCode() {
        let url = URL(string: "http://localhost:54545/callback?state=my-state")!
        XCTAssertThrowsError(try OAuthCoordinator.extractCode(from: url, expectedState: "my-state")) { error in
            XCTAssertTrue("\(error)".contains("No authorization code"), "Expected missing code error, got: \(error)")
        }
    }

    // MARK: - Gemini auth URL

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

    // MARK: - Project ID fetching

    func testFetchProjectIDUsesCorrectIdeTypeForGemini() async throws {
        let mockClient = MockHTTPClient()

        mockClient.enqueue(.json([
            "cloudaicompanionProject": "gemini-proj-123"
        ]))

        let projectId = try await GeminiAuthProvider.fetchProjectID(
            accessToken: "test-token",
            httpClient: mockClient
        )

        XCTAssertEqual(projectId, "gemini-proj-123")

        let request = try XCTUnwrap(mockClient.capturedRequests.first)
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try XCTUnwrap(body["metadata"] as? [String: String])
        XCTAssertEqual(metadata["ideType"], "IDE_UNSPECIFIED")
    }

    func testFetchProjectIDUsesCorrectIdeTypeForAntigravity() async throws {
        let mockClient = MockHTTPClient()

        mockClient.enqueue(.json([
            "cloudaicompanionProject": "ag-proj-456"
        ]))

        let projectId = try await AntigravityAuthProvider.fetchProjectID(
            accessToken: "test-token",
            httpClient: mockClient
        )

        XCTAssertEqual(projectId, "ag-proj-456")

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

        mockClient.enqueue(.error(500, message: "test"))

        let service = LLMService(
            session: session,
            loggingConfig: LLMLoggingConfig(),
            httpClient: mockClient
        )

        let stream = service.chatStream(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hi")])]
        )
        do {
            for try await _ in stream {}
        } catch {
            // Expected 500 error
        }

        let request = try XCTUnwrap(mockClient.capturedRequests.first)
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["project"] as? String, "my-gemini-project")
    }
}

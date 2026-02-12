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
        let redirectURI = GoogleOAuthProvider.redirectURI(for: .geminiCLI)
        XCTAssertEqual(redirectURI, "http://localhost:8085/oauth2callback")
    }

    func testAntigravityRedirectURI() {
        let redirectURI = GoogleOAuthProvider.redirectURI(for: .antigravity)
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

    func testBuildAuthURLContainsCorrectRedirectURI() {
        let redirectURI = GoogleOAuthProvider.redirectURI(for: .geminiCLI)
        let authURL = GoogleOAuthProvider.buildAuthURL(
            provider: .geminiCLI,
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

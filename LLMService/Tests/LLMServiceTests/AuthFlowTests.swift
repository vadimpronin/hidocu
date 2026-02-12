import XCTest
@testable import LLMService

final class AuthFlowTests: XCTestCase {
    func testLoginCallsSave() async throws {
        let mockClient = MockHTTPClient()
        let mockLauncher = MockOAuthLauncher()
        let session = MockAccountSession(provider: .claudeCode)

        // Set up callback URL with auth code
        mockLauncher.callbackURL = URL(string: "llmservice://auth/callback?code=test-code&state=test-state")

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
}

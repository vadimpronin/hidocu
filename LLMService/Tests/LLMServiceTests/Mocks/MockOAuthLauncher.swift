import Foundation
@testable import LLMService

final class MockOAuthLauncher: OAuthSessionLauncher, @unchecked Sendable {
    var callbackURL: URL?
    var capturedAuthURL: URL?
    var shouldFail = false

    @MainActor
    func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
        capturedAuthURL = url
        if shouldFail {
            throw LLMServiceError(traceId: "", message: "Mock OAuth failure")
        }
        guard let callback = callbackURL else {
            throw LLMServiceError(traceId: "", message: "No callback URL configured")
        }
        return callback
    }
}

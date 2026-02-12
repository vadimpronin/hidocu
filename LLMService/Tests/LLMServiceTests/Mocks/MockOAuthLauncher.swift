import Foundation
@testable import LLMService

final class MockOAuthLauncher: OAuthSessionLauncher, @unchecked Sendable {
    var callbackURL: URL?
    var capturedAuthURL: URL?
    var shouldFail = false
    /// When true, constructs callback URL by echoing the state from the auth URL
    var echoStateInCallback = false

    @MainActor
    func authenticate(url: URL, callbackScheme: String?) async throws -> URL {
        capturedAuthURL = url
        if shouldFail {
            throw LLMServiceError(traceId: "", message: "Mock OAuth failure")
        }
        guard let callback = callbackURL else {
            if echoStateInCallback, let scheme = callbackScheme {
                // Extract state from auth URL and construct callback with matching state
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let state = components?.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
                return URL(string: "\(scheme)://auth/callback?code=test-code&state=\(state)")!
            }
            throw LLMServiceError(traceId: "", message: "No callback URL configured")
        }
        return callback
    }
}

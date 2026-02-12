import Foundation

public protocol OAuthSessionLauncher: Sendable {
    @MainActor func authenticate(url: URL, callbackScheme: String?) async throws -> URL
}

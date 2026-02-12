import Foundation
import OSLog

internal let llmServiceLogger = Logger(subsystem: "com.llmservice", category: "LLMService")

public final class LLMService: @unchecked Sendable {
    public let session: LLMAccountSession
    public let loggingConfig: LLMLoggingConfig
    public var proxyURL: URL?

    internal let httpClient: HTTPClient
    internal let oauthLauncher: OAuthSessionLauncher
    internal let traceManager: LLMTraceManager
    internal var lastResponseHeaders: [String: String] = [:]

    internal static let traceBodyCapBytes = 512 * 1024

    // MARK: - Initialization

    public convenience init(session: LLMAccountSession, loggingConfig: LLMLoggingConfig = LLMLoggingConfig()) {
        let client = URLSessionHTTPClient()
        let launcher = SystemOAuthLauncher()
        self.init(session: session, loggingConfig: loggingConfig, httpClient: client, oauthLauncher: launcher)
    }

    internal init(
        session: LLMAccountSession,
        loggingConfig: LLMLoggingConfig,
        httpClient: HTTPClient,
        oauthLauncher: OAuthSessionLauncher
    ) {
        self.session = session
        self.loggingConfig = loggingConfig
        self.httpClient = httpClient
        self.oauthLauncher = oauthLauncher
        self.traceManager = LLMTraceManager(config: loggingConfig)
    }

    // MARK: - Auth

    public func login() async throws {
        try await OAuthCoordinator.login(
            session: session,
            httpClient: httpClient,
            oauthLauncher: oauthLauncher
        )
    }
}

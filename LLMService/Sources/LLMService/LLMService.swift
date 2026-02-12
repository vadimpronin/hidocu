import Foundation
import OSLog

internal let llmServiceLogger = Logger(subsystem: "com.llmservice", category: "LLMService")

public final class LLMService: @unchecked Sendable {
    public let session: LLMAccountSession
    public let loggingConfig: LLMLoggingConfig
    public var proxyURL: URL?

    internal let httpClient: HTTPClient
    internal let traceManager: LLMTraceManager
    internal var lastResponseHeaders: [String: String] = [:]

    // MARK: - Initialization

    public convenience init(session: LLMAccountSession, loggingConfig: LLMLoggingConfig = LLMLoggingConfig()) {
        let client = URLSessionHTTPClient()
        self.init(session: session, loggingConfig: loggingConfig, httpClient: client)
    }

    internal init(
        session: LLMAccountSession,
        loggingConfig: LLMLoggingConfig,
        httpClient: HTTPClient
    ) {
        self.session = session
        self.loggingConfig = loggingConfig
        self.httpClient = httpClient
        self.traceManager = LLMTraceManager(config: loggingConfig)
    }

    // MARK: - Auth

    public func login() async throws {
        let tracingClient = makeTracingClient(traceId: UUID().uuidString, method: "login")
        try await OAuthCoordinator.login(
            session: session,
            httpClient: tracingClient
        )
    }
}

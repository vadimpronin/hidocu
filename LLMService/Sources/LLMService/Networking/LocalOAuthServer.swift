import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.llmservice", category: "LocalOAuthServer")

/// Actor-based local HTTP server for receiving OAuth callbacks.
///
/// Starts a TCP listener on the specified port, awaits a single HTTP request
/// to the callback path, extracts the query parameters, and returns the full
/// callback URL. Supports timeout and task cancellation.
actor LocalOAuthServer {
    private let port: UInt16
    private let callbackPath: String
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var isCancelled = false

    init(port: UInt16, callbackPath: String) {
        self.port = port
        self.callbackPath = callbackPath
        logger.info("LocalOAuthServer init: port=\(port), callbackPath=\(callbackPath)")
    }

    /// Starts the server and waits for the OAuth callback.
    ///
    /// The `onListenerReady` closure is called synchronously after the TCP listener
    /// is started — use it to open the browser. This ensures the server is listening
    /// before the browser navigates to the OAuth provider.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait for callback (default: 120 seconds)
    ///   - onListenerReady: Called after the listener starts; use to open the authorization URL in the browser
    /// - Returns: Full callback URL with query parameters (e.g., `http://localhost:8085/oauth2callback?code=xxx&state=yyy`)
    /// - Throws: `CancellationError`, `LLMServiceError`, or network errors
    func awaitCallback(timeout: TimeInterval = 120, onListenerReady: @Sendable () -> Void = {}) async throws -> URL {
        logger.info("awaitCallback: entering, timeout=\(timeout)")
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if isCancelled {
                    logger.warning("awaitCallback: already cancelled before starting")
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation

                do {
                    logger.info("awaitCallback: calling startListener()")
                    try startListener()
                    logger.info("awaitCallback: startListener() returned, calling onListenerReady()")
                    onListenerReady()
                    logger.info("awaitCallback: onListenerReady() returned, scheduling timeout")
                    scheduleTimeout(timeout)
                } catch {
                    logger.error("awaitCallback: startListener() threw: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    self.continuation = nil
                }
            }
        } onCancel: {
            logger.info("awaitCallback: task cancellation handler fired")
            Task { await self.cancel() }
        }
    }

    /// Cancels the ongoing callback wait, stopping the listener.
    func cancel() {
        logger.info("cancel: called, isCancelled=\(self.isCancelled)")
        isCancelled = true
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        stopListener()
    }

    // MARK: - Private

    private func startListener() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = false

        guard let portNW = NWEndpoint.Port(rawValue: port) else {
            logger.error("startListener: invalid port \(self.port)")
            throw LLMServiceError(
                traceId: "local-oauth-server",
                message: "Invalid port: \(port)"
            )
        }

        logger.info("startListener: creating NWListener on port \(self.port)")
        listener = try NWListener(using: params, on: portNW)
        logger.info("startListener: NWListener created successfully")

        listener?.stateUpdateHandler = { [weak self] state in
            let stateDesc: String
            switch state {
            case .setup: stateDesc = "setup"
            case .waiting(let err): stateDesc = "waiting(\(err))"
            case .ready: stateDesc = "ready"
            case .failed(let err): stateDesc = "failed(\(err))"
            case .cancelled: stateDesc = "cancelled"
            @unknown default: stateDesc = "unknown"
            }
            logger.info("stateUpdateHandler: state=\(stateDesc)")
            Task {
                await self?.handleListenerState(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            logger.info("newConnectionHandler: received new connection from \(String(describing: connection.endpoint))")
            Task {
                await self?.handleConnection(connection)
            }
        }

        logger.info("startListener: calling listener.start()")
        listener?.start(queue: .global(qos: .userInitiated))
        logger.info("startListener: listener.start() returned")
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            logger.error("handleListenerState: FAILED — \(error.localizedDescription)")
            if case .posix(let code) = error, code == .EADDRINUSE {
                continuation?.resume(throwing: LLMServiceError(
                    traceId: "local-oauth-server",
                    message: "Port \(port) is already in use"
                ))
            } else {
                continuation?.resume(throwing: LLMServiceError(
                    traceId: "local-oauth-server",
                    message: "Listener failed: \(error.localizedDescription)"
                ))
            }
            continuation = nil
            stopListener()
        case .ready:
            logger.info("handleListenerState: READY — listening on port \(self.port)")
        case .cancelled:
            logger.info("handleListenerState: CANCELLED")
        case .waiting(let error):
            logger.warning("handleListenerState: WAITING — \(error.localizedDescription)")
        default:
            logger.info("handleListenerState: other state")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        logger.info("handleConnection: starting connection")
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            let dataLen = data?.count ?? 0
            logger.info("handleConnection: receive callback — dataLen=\(dataLen), isComplete=\(isComplete), error=\(String(describing: error))")
            Task {
                await self?.processRequest(data: data, connection: connection, isComplete: isComplete, error: error)
            }
        }
    }

    private func processRequest(data: Data?, connection: NWConnection, isComplete: Bool, error: NWError?) {
        guard let data = data, let request = String(data: data, encoding: .utf8) else {
            logger.error("processRequest: no data or not UTF-8, cancelling connection")
            connection.cancel()
            return
        }

        logger.info("processRequest: raw request length=\(data.count)")
        // Log first line only (contains path, not sensitive)
        let firstLine = request.components(separatedBy: .newlines).first ?? "(empty)"
        logger.info("processRequest: request line: \(firstLine)")

        // Parse HTTP request line (e.g., "GET /oauth2callback?code=xxx&state=yyy HTTP/1.1")
        guard let urlString = firstLine.components(separatedBy: " ").dropFirst().first else {
            logger.error("processRequest: could not parse URL from request line")
            connection.cancel()
            return
        }

        // Only handle requests to our callback path
        guard urlString.starts(with: callbackPath) else {
            logger.warning("processRequest: path '\(urlString)' does not start with '\(self.callbackPath)' — returning 404")
            sendResponse(connection: connection, html: "<h1>404 Not Found</h1>", statusCode: 404)
            return
        }

        // Parse query parameters
        guard let url = URL(string: "http://localhost:\(port)" + urlString) else {
            logger.error("processRequest: could not construct URL from 'http://localhost:\(self.port)\(urlString)'")
            connection.cancel()
            return
        }

        logger.info("processRequest: parsed callback URL successfully")

        // Check for error parameter
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let errorDescription = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? error
            logger.error("processRequest: OAuth error: \(errorDescription)")
            sendResponse(connection: connection, html: "<h1>Authentication Failed</h1><p>\(htmlEscape(errorDescription))</p>", statusCode: 400)
            continuation?.resume(throwing: LLMServiceError(
                traceId: "oauth-callback",
                message: "Authentication failed: \(errorDescription)"
            ))
            continuation = nil
            stopListener()
            return
        }

        // Send success response to browser
        let successHTML = """
        <html>
        <head><title>Authentication Successful</title></head>
        <body style="font-family: system-ui; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0;">
            <div style="text-align: center;">
                <h1 style="color: #4CAF50;">✓ Authentication Successful</h1>
                <p>You can close this window and return to the application.</p>
            </div>
        </body>
        </html>
        """
        logger.info("processRequest: sending success response and resuming continuation")
        sendResponse(connection: connection, html: successHTML, statusCode: 200)

        // Resume continuation with the full callback URL and cancel timeout
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: url)
        continuation = nil
        stopListener()
        logger.info("processRequest: done — listener stopped")
    }

    private func sendResponse(connection: NWConnection, html: String, statusCode: Int) {
        let statusText = statusCode == 200 ? "OK" : (statusCode == 404 ? "Not Found" : "Bad Request")
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """

        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    logger.error("sendResponse: send error: \(error.localizedDescription)")
                }
                connection.cancel()
            })
        } else {
            connection.cancel()
        }
    }

    private func scheduleTimeout(_ timeout: TimeInterval) {
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

            if continuation != nil {
                logger.error("scheduleTimeout: TIMED OUT after \(timeout)s")
                continuation?.resume(throwing: LLMServiceError(
                    traceId: "oauth-callback",
                    message: "OAuth callback timed out after \(timeout) seconds"
                ))
                continuation = nil
                stopListener()
            }
        }
    }

    private func stopListener() {
        logger.info("stopListener: cancelling listener")
        listener?.cancel()
        listener = nil
    }

    private func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

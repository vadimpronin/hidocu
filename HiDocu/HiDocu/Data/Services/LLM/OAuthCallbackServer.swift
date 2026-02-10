//
//  OAuthCallbackServer.swift
//  HiDocu
//
//  Local HTTP server for receiving OAuth callbacks from LLM providers.
//

import Foundation
import Network
import AppKit

/// Result from OAuth callback containing authorization code and state.
struct OAuthResult: Sendable {
    let code: String
    let state: String
}

/// Actor-isolated HTTP server for handling OAuth callbacks.
///
/// Usage:
/// ```swift
/// let server = OAuthCallbackServer(port: 54545, callbackPath: "/callback")
/// let authURL = URL(string: "https://example.com/oauth/authorize?...")!
/// let result = try await server.awaitCallback(authorizationURL: authURL)
/// ```
actor OAuthCallbackServer {
    private let port: UInt16
    private let callbackPath: String
    private let provider: LLMProvider
    private var listener: NWListener?
    private var continuation: CheckedContinuation<OAuthResult, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(port: UInt16, callbackPath: String, provider: LLMProvider) {
        self.port = port
        self.callbackPath = callbackPath
        self.provider = provider
    }

    /// Starts the server, opens the authorization URL in the browser, and waits for the callback.
    ///
    /// - Parameters:
    ///   - authorizationURL: OAuth authorization URL to open in browser
    ///   - timeout: Maximum time to wait for callback (default: 300 seconds)
    /// - Returns: OAuth result containing code and state
    /// - Throws: `LLMError.portInUse`, `LLMError.oauthTimeout`, or network errors
    func awaitCallback(authorizationURL: URL, timeout: TimeInterval = 300) async throws -> OAuthResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            do {
                try startListener()
                openBrowser(url: authorizationURL)
                scheduleTimeout(timeout)
            } catch {
                continuation.resume(throwing: error)
                self.continuation = nil
            }
        }
    }

    // MARK: - Private

    private func startListener() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = false

        guard let portNW = NWEndpoint.Port(rawValue: port) else {
            throw LLMError.portInUse(port: port)
        }

        listener = try NWListener(using: params, on: portNW)

        listener?.stateUpdateHandler = { [weak self] state in
            Task {
                await self?.handleListenerState(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .failed(let error):
            if case .posix(let code) = error, code == .EADDRINUSE {
                continuation?.resume(throwing: LLMError.portInUse(port: port))
            } else {
                continuation?.resume(throwing: LLMError.networkError(underlying: error.localizedDescription))
            }
            continuation = nil
            stopListener()
        case .ready:
            break
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            Task {
                await self?.processRequest(data: data, connection: connection, isComplete: isComplete, error: error)
            }
        }
    }

    private func processRequest(data: Data?, connection: NWConnection, isComplete: Bool, error: NWError?) {
        guard let data = data, let request = String(data: data, encoding: .utf8) else {
            connection.cancel()
            return
        }

        // Parse HTTP request line
        guard let firstLine = request.components(separatedBy: .newlines).first,
              let urlString = firstLine.components(separatedBy: " ").dropFirst().first else {
            connection.cancel()
            return
        }

        // Only handle requests to our callback path
        guard urlString.starts(with: callbackPath) else {
            sendResponse(connection: connection, html: "<h1>404 Not Found</h1>", statusCode: 404)
            return
        }

        // Parse query parameters
        guard let url = URL(string: "http://localhost" + urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            connection.cancel()
            return
        }

        // Check for error parameter
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            let errorDescription = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? error
            sendResponse(connection: connection, html: "<h1>Authentication Failed</h1><p>\(errorDescription)</p>", statusCode: 400)
            continuation?.resume(throwing: LLMError.authenticationFailed(provider: provider, detail: errorDescription))
            continuation = nil
            stopListener()
            return
        }

        // Extract code and state
        guard var code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            sendResponse(connection: connection, html: "<h1>Error</h1><p>No authorization code received.</p>", statusCode: 400)
            continuation?.resume(throwing: LLMError.invalidResponse(detail: "No code parameter in callback"))
            continuation = nil
            stopListener()
            return
        }

        // Handle Claude's code#state format
        var state = components.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        if code.contains("#") {
            let parts = code.split(separator: "#", maxSplits: 1)
            code = String(parts[0])
            if parts.count > 1 {
                state = String(parts[1])
            }
        }

        // Send success response to browser
        let successHTML = """
        <html>
        <head><title>Authentication Successful</title></head>
        <body style="font-family: system-ui; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0;">
            <div style="text-align: center;">
                <h1 style="color: #4CAF50;">✓ Authentication Successful</h1>
                <p>You can close this window and return to HiDocu.</p>
            </div>
        </body>
        </html>
        """
        sendResponse(connection: connection, html: successHTML, statusCode: 200)

        // Resume continuation with result and cancel timeout
        let result = OAuthResult(code: code, state: state)
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: result)
        continuation = nil
        stopListener()
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
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else {
            connection.cancel()
        }
    }

    private func openBrowser(url: URL) {
        Task { @MainActor in
            NSWorkspace.shared.open(url)
        }
    }

    private func scheduleTimeout(_ timeout: TimeInterval) {
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

            if continuation != nil {
                continuation?.resume(throwing: LLMError.oauthTimeout)
                continuation = nil
                stopListener()
            }
        }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }
}

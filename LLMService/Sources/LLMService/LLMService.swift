import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmservice", category: "LLMService")

public final class LLMService: @unchecked Sendable {
    public let session: LLMAccountSession
    public let loggingConfig: LLMLoggingConfig
    public var proxyURL: URL?

    internal let httpClient: HTTPClient
    internal let oauthLauncher: OAuthSessionLauncher
    private let traceManager: LLMTraceManager
    private var lastResponseHeaders: [String: String] = [:]

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

    // MARK: - Chat (aggregates stream into full response)

    public func chat(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig? = nil,
        idempotencyKey: String? = nil
    ) async throws -> LLMResponse {
        let traceId = UUID().uuidString
        let stream = chatStream(modelId: modelId, messages: messages, thinking: thinking, idempotencyKey: idempotencyKey)

        var responseId = ""
        var parts: [LLMResponsePart] = []
        var currentPartType: String = ""
        var currentText = ""
        var currentToolId = ""
        var currentToolName = ""
        var lastUsage: LLMUsage?

        for try await chunk in stream {
            responseId = chunk.id
            if let usage = chunk.usage {
                lastUsage = usage
            }

            switch chunk.partType {
            case .text:
                if currentPartType != "text" {
                    flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)
                    currentPartType = "text"
                }
                currentText += chunk.delta

            case .thinking:
                if currentPartType != "thinking" {
                    flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)
                    currentPartType = "thinking"
                }
                currentText += chunk.delta

            case .toolCall(let id, let function):
                let key = "tool:\(id):\(function)"
                if currentPartType != key {
                    flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)
                    currentPartType = key
                    currentToolId = id
                    currentToolName = function
                }
                currentText += chunk.delta
            }
        }

        flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)

        return LLMResponse(
            id: responseId,
            model: modelId,
            traceId: traceId,
            content: parts,
            usage: lastUsage
        )
    }

    private func flushPart(
        _ parts: inout [LLMResponsePart],
        type: inout String,
        text: inout String,
        toolId: inout String,
        toolName: inout String
    ) {
        guard !type.isEmpty else { return }
        switch type {
        case "text":
            if !text.isEmpty { parts.append(.text(text)) }
        case "thinking":
            if !text.isEmpty { parts.append(.thinking(text)) }
        default:
            if type.hasPrefix("tool:") {
                parts.append(.toolCall(id: toolId, function: toolName, arguments: text))
            }
        }
        text = ""
        type = ""
        toolId = ""
        toolName = ""
    }

    // MARK: - Chat Stream

    public func chatStream(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig? = nil,
        idempotencyKey: String? = nil
    ) -> AsyncThrowingStream<LLMChatChunk, Error> {
        let traceId = UUID().uuidString

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let provider = try self.resolveProvider()
                    logger.info("[\(traceId)] chatStream: provider=\(provider.provider.rawValue), model=\(modelId)")

                    let credentials = try await self.getCredentialsWithRefresh(traceId: traceId)
                    logger.info("[\(traceId)] chatStream: got credentials, hasAccessToken=\(credentials.accessToken != nil)")

                    let request = try provider.buildStreamRequest(
                        modelId: modelId,
                        messages: messages,
                        thinking: thinking,
                        credentials: credentials,
                        traceId: traceId
                    )
                    logger.info("[\(traceId)] chatStream: request URL=\(request.url?.absoluteString ?? "nil"), bodySize=\(request.httpBody?.count ?? 0)")

                    let (byteStream, response) = try await self.executeWithRetry(
                        request: request,
                        traceId: traceId
                    )
                    logger.info("[\(traceId)] chatStream: response statusCode=\(response.statusCode)")

                    let startTime = Date()
                    let reqDetails = LLMTraceEntry.HTTPDetails(
                        url: request.url?.absoluteString,
                        method: request.httpMethod,
                        headers: request.allHTTPHeaderFields,
                        body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
                    )

                    guard (200..<300).contains(response.statusCode) else {
                        var errorData = Data()
                        for try await byte in byteStream {
                            errorData.append(byte)
                        }
                        let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        logger.error("[\(traceId)] chatStream: API error \(response.statusCode): \(errorMsg)")

                        await self.traceManager.record(LLMTraceEntry(
                            traceId: traceId,
                            requestId: idempotencyKey ?? traceId,
                            provider: provider.provider.rawValue,
                            accountIdentifier: self.session.info.identifier,
                            method: "chatStream",
                            isStreaming: true,
                            request: reqDetails,
                            response: LLMTraceEntry.HTTPDetails(body: errorMsg, statusCode: response.statusCode),
                            error: errorMsg,
                            duration: Date().timeIntervalSince(startTime)
                        ))

                        throw LLMServiceError(traceId: traceId, message: errorMsg, statusCode: response.statusCode)
                    }

                    var parser = provider.createStreamParser()
                    var lineBuffer = ""
                    var responseText = ""

                    for try await byte in byteStream {
                        let char = Character(UnicodeScalar(byte))
                        if char == "\n" {
                            if !lineBuffer.isEmpty {
                                let chunks = provider.parseStreamLine(lineBuffer, parser: &parser)
                                for chunk in chunks {
                                    responseText += chunk.delta
                                    continuation.yield(chunk)
                                }
                            }
                            lineBuffer = ""
                        } else {
                            lineBuffer.append(char)
                        }
                    }

                    if !lineBuffer.isEmpty {
                        let chunks = provider.parseStreamLine(lineBuffer, parser: &parser)
                        for chunk in chunks {
                            responseText += chunk.delta
                            continuation.yield(chunk)
                        }
                    }

                    await self.traceManager.record(LLMTraceEntry(
                        traceId: traceId,
                        requestId: idempotencyKey ?? traceId,
                        provider: provider.provider.rawValue,
                        accountIdentifier: self.session.info.identifier,
                        method: "chatStream",
                        isStreaming: true,
                        request: reqDetails,
                        response: LLMTraceEntry.HTTPDetails(
                            body: String(responseText.prefix(4096)),
                            statusCode: response.statusCode
                        ),
                        duration: Date().timeIntervalSince(startTime)
                    ))

                    logger.info("[\(traceId)] chatStream: stream completed successfully")
                    continuation.finish()
                } catch {
                    logger.error("[\(traceId)] chatStream: error — \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Inspection

    public func listModels() async throws -> [LLMModelInfo] {
        let provider = try resolveProvider()
        return provider.listModels()
    }

    public func getQuotaStatus(for modelId: String) async throws -> LLMQuotaStatus {
        let remaining = lastResponseHeaders["x-ratelimit-limit-requests"]
            .flatMap(Int.init)
        let resetStr = lastResponseHeaders["x-ratelimit-reset-requests"]
        let resetIn = parseResetTime(resetStr)

        return LLMQuotaStatus(
            modelId: modelId,
            isAvailable: remaining != 0,
            resetIn: resetIn,
            remainingRequests: remaining
        )
    }

    // MARK: - Debug

    public func exportHAR(lastMinutes: Int) async throws -> Data {
        logger.info("exportHAR: loading entries (last \(lastMinutes) min), storageDir=\(self.loggingConfig.storageDirectory?.path ?? "nil")")
        let entries = await traceManager.loadEntries(lastMinutes: lastMinutes)
        logger.info("exportHAR: loaded \(entries.count) entries, exporting as HAR")
        return try HARExporter.export(entries: entries)
    }

    public func cleanupLogs(olderThanDays days: Int) async throws {
        try await traceManager.cleanup(olderThanDays: days)
    }

    // MARK: - Internal

    private func resolveProvider() throws -> InternalProvider {
        switch session.info.provider {
        case .claudeCode:
            return ClaudeCodeProvider()
        case .geminiCLI:
            let projectId = session.info.metadata["project_id"] ?? ""
            return GeminiCLIProvider(projectId: projectId)
        case .antigravity:
            let projectId = session.info.metadata["project_id"] ?? ""
            return AntigravityProvider(projectId: projectId)
        }
    }

    private func getCredentialsWithRefresh(traceId: String) async throws -> LLMCredentials {
        let credentials = try await session.getCredentials()
        if let expiresAt = credentials.expiresAt, expiresAt <= Date() {
            return try await refreshAndSave(credentials: credentials, traceId: traceId)
        }
        return credentials
    }

    private func refreshAndSave(credentials: LLMCredentials, traceId: String) async throws -> LLMCredentials {
        guard let refreshToken = credentials.refreshToken else {
            throw LLMServiceError(traceId: traceId, message: "No refresh token available")
        }
        let newCredentials = try await TokenRefresher.refresh(
            provider: session.info.provider,
            refreshToken: refreshToken,
            httpClient: httpClient
        )
        try await session.save(info: session.info, credentials: newCredentials)
        return newCredentials
    }

    private func executeWithRetry(
        request: URLRequest,
        traceId: String
    ) async throws -> (AnyAsyncSequence<UInt8>, HTTPURLResponse) {
        let (bytes, response) = try await httpClient.bytes(for: request)

        captureRateLimitHeaders(from: response)

        if response.statusCode == 401 {
            let credentials = try await session.getCredentials()
            guard let refreshToken = credentials.refreshToken else {
                throw LLMServiceError(traceId: traceId, message: "Unauthorized and no refresh token", statusCode: 401)
            }
            let newCredentials = try await TokenRefresher.refresh(
                provider: session.info.provider,
                refreshToken: refreshToken,
                httpClient: httpClient
            )
            try await session.save(info: session.info, credentials: newCredentials)

            var newRequest = request
            let token = newCredentials.accessToken ?? newCredentials.apiKey ?? ""
            newRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (retryBytes, retryResponse) = try await httpClient.bytes(for: newRequest)
            captureRateLimitHeaders(from: retryResponse)
            return (retryBytes, retryResponse)
        }

        return (bytes, response)
    }

    private func captureRateLimitHeaders(from response: HTTPURLResponse) {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            let keyStr = "\(key)".lowercased()
            if keyStr.hasPrefix("x-ratelimit") {
                headers[keyStr] = "\(value)"
            }
        }
        if !headers.isEmpty {
            lastResponseHeaders = headers
        }
    }

    private func parseResetTime(_ value: String?) -> TimeInterval? {
        guard let str = value, !str.isEmpty else { return nil }

        // Raw number → treat as seconds
        if let raw = Double(str) {
            return raw
        }

        // Handle duration formats like "30s", "1m30s", "500ms"
        // Use a simple regex-free scan: collect number+suffix pairs
        var total: TimeInterval = 0
        var matched = false
        var remaining = str[str.startIndex...]

        while !remaining.isEmpty {
            // Skip non-digit prefix
            guard let digitStart = remaining.firstIndex(where: { $0.isNumber || $0 == "." }) else { break }
            remaining = remaining[digitStart...]

            // Collect digits
            let afterDigits = remaining.firstIndex(where: { !$0.isNumber && $0 != "." }) ?? remaining.endIndex
            guard let num = Double(remaining[remaining.startIndex..<afterDigits]) else { break }
            remaining = remaining[afterDigits...]

            // Check suffix
            if remaining.hasPrefix("ms") {
                total += num / 1000.0
                remaining = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...]
                matched = true
            } else if remaining.hasPrefix("h") {
                total += num * 3600
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                matched = true
            } else if remaining.hasPrefix("m") {
                total += num * 60
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                matched = true
            } else if remaining.hasPrefix("s") {
                total += num
                remaining = remaining[remaining.index(after: remaining.startIndex)...]
                matched = true
            } else {
                break
            }
        }

        return matched ? total : nil
    }
}

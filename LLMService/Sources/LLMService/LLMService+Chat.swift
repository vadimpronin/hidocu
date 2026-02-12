import Foundation
import OSLog

// MARK: - Chat (Smart Router)

extension LLMService {

    public func chat(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig? = nil,
        idempotencyKey: String? = nil
    ) async throws -> LLMResponse {
        let traceId = UUID().uuidString
        let provider = try resolveProvider()
        if provider.supportsNonStreaming {
            return try await chatNonStreamInternal(
                provider: provider,
                modelId: modelId,
                messages: messages,
                thinking: thinking,
                idempotencyKey: idempotencyKey,
                traceId: traceId,
                method: "chat"
            )
        } else {
            return try await aggregateStreamResponse(
                modelId: modelId,
                messages: messages,
                thinking: thinking,
                idempotencyKey: idempotencyKey,
                traceId: traceId
            )
        }
    }

    // MARK: - Non-Streaming Chat

    public func chatNonStream(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig? = nil,
        idempotencyKey: String? = nil
    ) async throws -> LLMResponse {
        let traceId = UUID().uuidString
        let provider = try resolveProvider()

        guard provider.supportsNonStreaming else {
            throw LLMServiceError(
                traceId: traceId,
                message: "Provider \(provider.provider.rawValue) does not support non-streaming requests"
            )
        }

        return try await chatNonStreamInternal(
            provider: provider,
            modelId: modelId,
            messages: messages,
            thinking: thinking,
            idempotencyKey: idempotencyKey,
            traceId: traceId,
            method: "chatNonStream"
        )
    }

    internal func chatNonStreamInternal(
        provider: InternalProvider,
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        idempotencyKey: String?,
        traceId: String,
        method: String
    ) async throws -> LLMResponse {
        llmServiceLogger.info("[\(traceId)] \(method): provider=\(provider.provider.rawValue), model=\(modelId)")

        let credentials = try await getCredentialsWithRefresh(traceId: traceId)
        let request = try provider.buildNonStreamRequest(
            modelId: modelId,
            messages: messages,
            thinking: thinking,
            credentials: credentials,
            traceId: traceId
        )

        let startTime = Date()
        let context = makeTraceContext(
            traceId: traceId,
            idempotencyKey: idempotencyKey,
            provider: provider,
            method: method,
            isStreaming: false,
            request: request,
            startTime: startTime
        )
        await notifyTraceSent(context)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await withRetry(request: request, traceId: traceId) {
                try await self.httpClient.data(for: $0)
            }
        } catch {
            await recordTrace(context, error: error.localizedDescription)
            throw Self.wrapError(error, traceId: traceId)
        }

        guard (200..<300).contains(response.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            llmServiceLogger.error("[\(traceId)] \(method): API error \(response.statusCode): \(errorBody)")

            await recordTrace(
                context,
                error: errorBody,
                response: LLMTraceEntry.HTTPDetails(from: response, body: errorBody)
            )

            throw LLMServiceError(traceId: traceId, message: errorBody, statusCode: response.statusCode)
        }

        let responseDetails = LLMTraceEntry.HTTPDetails(from: response, body: String(data: data, encoding: .utf8))

        let llmResponse: LLMResponse
        do {
            llmResponse = try provider.parseResponse(data: data, traceId: traceId)
        } catch {
            await recordTrace(context, error: error.localizedDescription, response: responseDetails)
            throw Self.wrapError(error, traceId: traceId)
        }

        await recordTrace(context, response: responseDetails)

        llmServiceLogger.info("[\(traceId)] \(method): completed successfully")
        return llmResponse
    }

    // MARK: - Chat Stream

    public func chatStream(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig? = nil,
        idempotencyKey: String? = nil
    ) -> AsyncThrowingStream<LLMChatChunk, Error> {
        chatStreamInternal(
            modelId: modelId,
            messages: messages,
            thinking: thinking,
            idempotencyKey: idempotencyKey,
            traceId: UUID().uuidString,
            method: "chatStream"
        )
    }

    internal func chatStreamInternal(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        idempotencyKey: String?,
        traceId: String,
        method: String
    ) -> AsyncThrowingStream<LLMChatChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let provider = try self.resolveProvider()
                    llmServiceLogger.info("[\(traceId)] \(method): provider=\(provider.provider.rawValue), model=\(modelId)")

                    let credentials = try await self.getCredentialsWithRefresh(traceId: traceId)
                    llmServiceLogger.info("[\(traceId)] \(method): got credentials, hasAccessToken=\(credentials.accessToken != nil)")

                    let request = try provider.buildStreamRequest(
                        modelId: modelId,
                        messages: messages,
                        thinking: thinking,
                        credentials: credentials,
                        traceId: traceId
                    )
                    llmServiceLogger.info("[\(traceId)] \(method): request URL=\(request.url?.absoluteString ?? "nil"), bodySize=\(request.httpBody?.count ?? 0)")

                    // Capture BEFORE network call so catch block can record trace
                    let startTime = Date()
                    let context = self.makeTraceContext(
                        traceId: traceId,
                        idempotencyKey: idempotencyKey,
                        provider: provider,
                        method: method,
                        isStreaming: true,
                        request: request,
                        startTime: startTime
                    )
                    await self.notifyTraceSent(context)

                    // Tracks whether trace was already recorded (non-200 error or success)
                    // so the catch block only records for genuinely new errors (network/mid-stream).
                    var isTraceRecorded = false
                    do {
                        let (byteStream, response) = try await self.withRetry(
                            request: request,
                            traceId: traceId
                        ) { req in
                            try await self.httpClient.bytes(for: req)
                        }
                        llmServiceLogger.info("[\(traceId)] \(method): response statusCode=\(response.statusCode)")

                        guard (200..<300).contains(response.statusCode) else {
                            var errorData = Data()
                            for try await byte in byteStream {
                                errorData.append(byte)
                            }
                            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                            llmServiceLogger.error("[\(traceId)] \(method): API error \(response.statusCode): \(errorMsg)")

                            await self.recordTrace(context, error: errorMsg, response: LLMTraceEntry.HTTPDetails(from: response, body: errorMsg))
                            isTraceRecorded = true

                            throw LLMServiceError(traceId: traceId, message: errorMsg, statusCode: response.statusCode)
                        }

                        var parser = provider.createStreamParser()
                        var lineBytes: [UInt8] = []
                        var rawLineSegments: [String] = []

                        for try await byte in byteStream {
                            if byte == 0x0A { // '\n'
                                if lineBytes.last == 0x0D { lineBytes.removeLast() } // strip \r from \r\n
                                let lineString = String(decoding: lineBytes, as: UTF8.self)
                                rawLineSegments.append(lineString + "\n")
                                if !lineBytes.isEmpty {
                                    let chunks = provider.parseStreamLine(lineString, parser: &parser)
                                    for chunk in chunks {
                                        continuation.yield(chunk)
                                    }
                                }
                                lineBytes.removeAll(keepingCapacity: true)
                            } else {
                                lineBytes.append(byte)
                            }
                        }

                        if !lineBytes.isEmpty {
                            let lineString = String(decoding: lineBytes, as: UTF8.self)
                            rawLineSegments.append(lineString + "\n")
                            let chunks = provider.parseStreamLine(lineString, parser: &parser)
                            for chunk in chunks {
                                continuation.yield(chunk)
                            }
                        }

                        await self.recordTrace(context, response: LLMTraceEntry.HTTPDetails(from: response, body: rawLineSegments.joined()))
                        isTraceRecorded = true

                        llmServiceLogger.info("[\(traceId)] \(method): stream completed successfully")
                        continuation.finish()
                    } catch {
                        // Network failure or mid-stream error — record trace only if
                        // not already recorded (e.g., by the non-200 guard block).
                        if !isTraceRecorded {
                            await self.recordTrace(context, error: error.localizedDescription)
                        }
                        throw Self.wrapError(error, traceId: traceId)
                    }
                } catch {
                    // Early failures (resolveProvider, getCredentials, buildStreamRequest)
                    // land here, as well as re-thrown errors from the inner catch.
                    llmServiceLogger.error("[\(traceId)] \(method): error — \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

import Foundation

final class TracingHTTPClient: HTTPClient, Sendable {

    struct Context: Sendable {
        let traceId: String
        let provider: String
        let method: String
        let accountIdentifier: String?
    }

    private let wrapped: HTTPClient
    private let traceManager: LLMTraceManager
    let context: Context

    init(wrapped: HTTPClient, traceManager: LLMTraceManager, context: Context) {
        self.wrapped = wrapped
        self.traceManager = traceManager
        self.context = context
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let requestId = UUID().uuidString
        let requestDetails = LLMTraceEntry.HTTPDetails(from: request)
        let startTime = Date()

        await traceManager.notifySent(LLMTraceEntry(
            traceId: context.traceId,
            requestId: requestId,
            provider: context.provider,
            accountIdentifier: context.accountIdentifier,
            method: context.method,
            isStreaming: false,
            request: requestDetails
        ))

        do {
            let (data, response) = try await wrapped.data(for: request)
            let body = String(data: data, encoding: .utf8)
            let responseDetails = LLMTraceEntry.HTTPDetails(from: response, body: body)
            let isError = !(200..<300).contains(response.statusCode)

            await traceManager.record(LLMTraceEntry(
                traceId: context.traceId,
                requestId: requestId,
                provider: context.provider,
                accountIdentifier: context.accountIdentifier,
                method: context.method,
                isStreaming: false,
                request: requestDetails,
                response: responseDetails,
                error: isError ? body : nil,
                duration: Date().timeIntervalSince(startTime)
            ))
            return (data, response)
        } catch {
            await traceManager.record(LLMTraceEntry(
                traceId: context.traceId,
                requestId: requestId,
                provider: context.provider,
                accountIdentifier: context.accountIdentifier,
                method: context.method,
                isStreaming: false,
                request: requestDetails,
                error: error.localizedDescription,
                duration: Date().timeIntervalSince(startTime)
            ))
            throw error
        }
    }

    // Passthrough — streaming is handled by chat's manual TraceContext-based tracing.
    func bytes(for request: URLRequest) async throws -> (AnyAsyncSequence<UInt8>, HTTPURLResponse) {
        try await wrapped.bytes(for: request)
    }
}

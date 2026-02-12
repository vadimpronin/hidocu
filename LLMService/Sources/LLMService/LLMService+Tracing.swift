import Foundation

// MARK: - Tracing Helpers

internal struct TraceContext: Sendable {
    let traceId: String
    let requestId: String
    let provider: String
    let accountIdentifier: String?
    let method: String
    let isStreaming: Bool
    let request: LLMTraceEntry.HTTPDetails
    let startTime: Date
}

extension LLMService {

    internal func makeTraceContext(
        traceId: String,
        idempotencyKey: String?,
        provider: InternalProvider,
        method: String,
        isStreaming: Bool,
        request: URLRequest,
        startTime: Date
    ) -> TraceContext {
        TraceContext(
            traceId: traceId,
            requestId: idempotencyKey ?? traceId,
            provider: provider.provider.rawValue,
            accountIdentifier: session.info.identifier,
            method: method,
            isStreaming: isStreaming,
            request: LLMTraceEntry.HTTPDetails(from: request),
            startTime: startTime
        )
    }

    internal func recordTrace(_ context: TraceContext, response: LLMTraceEntry.HTTPDetails) async {
        await traceManager.record(LLMTraceEntry(
            traceId: context.traceId,
            requestId: context.requestId,
            provider: context.provider,
            accountIdentifier: context.accountIdentifier,
            method: context.method,
            isStreaming: context.isStreaming,
            request: context.request,
            response: response,
            duration: Date().timeIntervalSince(context.startTime)
        ))
    }

    internal func recordTrace(_ context: TraceContext, error: String, response: LLMTraceEntry.HTTPDetails? = nil) async {
        await traceManager.record(LLMTraceEntry(
            traceId: context.traceId,
            requestId: context.requestId,
            provider: context.provider,
            accountIdentifier: context.accountIdentifier,
            method: context.method,
            isStreaming: context.isStreaming,
            request: context.request,
            response: response,
            error: error,
            duration: Date().timeIntervalSince(context.startTime)
        ))
    }

    internal func notifyTraceSent(_ context: TraceContext) async {
        await traceManager.notifySent(LLMTraceEntry(
            traceId: context.traceId,
            requestId: context.requestId,
            provider: context.provider,
            accountIdentifier: context.accountIdentifier,
            method: context.method,
            isStreaming: context.isStreaming,
            request: context.request
        ))
    }

    internal func makeTracingClient(traceId: String, method: String) -> TracingHTTPClient {
        TracingHTTPClient(
            wrapped: httpClient,
            traceManager: traceManager,
            context: .init(
                traceId: traceId,
                provider: session.info.provider.rawValue,
                method: method,
                accountIdentifier: session.info.identifier
            )
        )
    }

    internal static func wrapError(_ error: Error, traceId: String) -> Error {
        if let serviceError = error as? LLMServiceError {
            return serviceError
        }
        return LLMServiceError(traceId: traceId, message: error.localizedDescription, underlyingError: error)
    }

}

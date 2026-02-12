import Foundation
import OSLog

// MARK: - Inspection & Debug

extension LLMService {

    public func listModels() async throws -> [LLMModelInfo] {
        let provider = try resolveProvider()
        let traceId = UUID().uuidString
        let credentials = try await getCredentialsWithRefresh(traceId: traceId)
        let tracingClient = makeTracingClient(traceId: traceId, method: "listModels")
        return try await provider.listModels(credentials: credentials, httpClient: tracingClient)
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

    public func exportHAR(lastMinutes: Int) async throws -> Data {
        llmServiceLogger.info("exportHAR: loading entries (last \(lastMinutes) min), storageDir=\(self.loggingConfig.storageDirectory?.path ?? "nil")")
        let entries = await traceManager.loadEntries(lastMinutes: lastMinutes)
        llmServiceLogger.info("exportHAR: loaded \(entries.count) entries, exporting as HAR")
        return try HARExporter.export(entries: entries)
    }

    public func cleanupLogs(olderThanDays days: Int) async throws {
        try await traceManager.cleanup(olderThanDays: days)
    }
}

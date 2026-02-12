import Foundation
import OSLog

actor LLMTraceManager {
    private let config: LLMLoggingConfig
    private let redactor: Bool

    init(config: LLMLoggingConfig) {
        self.config = config
        self.redactor = config.shouldMaskTokens
    }

    /// Record a trace entry and write to disk if storageDirectory is configured
    func record(_ entry: LLMTraceEntry) {
        let category = "\(entry.provider).\(entry.method).\(entry.isStreaming ? "stream" : "sync")"
        let logger = Logger(subsystem: config.subsystem, category: category)

        if let error = entry.error {
            logger.error("[\(entry.traceId)] Error: \(error)")
        } else {
            logger.debug("[\(entry.traceId)] \(entry.method) -> \(entry.response?.statusCode ?? 0)")
        }

        guard let storageDir = config.storageDirectory else { return }

        var entryToWrite = entry
        if redactor {
            entryToWrite = redactEntry(entry)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "\(formatter.string(from: entry.timestamp))_\(entry.traceId).json"
        let fileURL = storageDir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entryToWrite)
            try data.write(to: fileURL)
        } catch {
            logger.error("[\(entry.traceId)] Failed to write trace: \(error.localizedDescription)")
        }
    }

    private func redactEntry(_ entry: LLMTraceEntry) -> LLMTraceEntry {
        var redacted = entry

        let reqHeaders = entry.request.headers.map { LLMRedactor.redactHeaders($0) }
        let reqBody = entry.request.body
            .flatMap { $0.data(using: .utf8) }
            .map { LLMRedactor.redactJSONBody($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        redacted.request = LLMTraceEntry.HTTPDetails(
            url: entry.request.url,
            method: entry.request.method,
            headers: reqHeaders,
            body: reqBody,
            statusCode: entry.request.statusCode
        )

        if let resp = entry.response {
            let respHeaders = resp.headers.map { LLMRedactor.redactHeaders($0) }
            let respBody = resp.body
                .flatMap { $0.data(using: .utf8) }
                .map { LLMRedactor.redactJSONBody($0) }
                .flatMap { String(data: $0, encoding: .utf8) }
            redacted.response = LLMTraceEntry.HTTPDetails(
                url: resp.url,
                method: resp.method,
                headers: respHeaders,
                body: respBody,
                statusCode: resp.statusCode
            )
        }

        return redacted
    }

    /// Load trace entries from disk within a time range
    func loadEntries(lastMinutes: Int) -> [LLMTraceEntry] {
        guard let storageDir = config.storageDirectory else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(lastMinutes) * 60)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        var entries: [LLMTraceEntry] = []
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate,
                  modDate >= cutoff else { continue }
            guard let data = try? Data(contentsOf: file),
                  let entry = try? decoder.decode(LLMTraceEntry.self, from: data) else { continue }
            entries.append(entry)
        }
        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    /// Clean up old trace files
    func cleanup(olderThanDays days: Int) throws {
        guard let storageDir = config.storageDirectory else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let files = try FileManager.default.contentsOfDirectory(
            at: storageDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for file in files where file.pathExtension == "json" {
            if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = attrs.contentModificationDate,
               modDate < cutoff {
                try FileManager.default.removeItem(at: file)
            }
        }
    }
}

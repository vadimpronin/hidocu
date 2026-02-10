//
//  APIDebugLogger.swift
//  HiDocu
//
//  Debug logging service for LLM API requests and responses.
//  Writes full request/response payloads to individual JSON files for debugging.
//

import Foundation

// MARK: - Debug Log Entry Model

/// Full record of an LLM API request/response, serialized to a JSON file.
struct APIDebugLogEntry: Codable, Sendable, Identifiable {
    let id: String
    let timestamp: Date
    let account: String?
    let job: JobContext
    let provider: String
    let model: String
    let request: RequestLog
    let response: ResponseLog
    let durationMs: Int

    struct JobContext: Codable, Sendable {
        let type: String
        let documentId: Int64?
        let sourceId: Int64?
        let transcriptId: Int64?
    }

    struct RequestLog: Codable, Sendable {
        let url: String
        let method: String
        let headers: [String: String]
        let body: String
    }

    struct ResponseLog: Codable, Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: String
    }
}

// MARK: - APIDebugLogger

/// Thread-safe debug logger that writes full LLM API request/response payloads to individual JSON files.
///
/// Each API call is saved as a separate JSON file in `{dataDirectory}/debug-logs/`.
/// Logging is gated by an `isEnabled` flag that maps to the user's settings.
/// File writes are performed asynchronously to avoid blocking API calls.
actor APIDebugLogger {

    // MARK: - Properties

    private var isEnabled: Bool
    private var baseDirectory: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// URL of the debug logs directory.
    var logDirectoryURL: URL {
        baseDirectory.appendingPathComponent("debug-logs", isDirectory: true)
    }

    // MARK: - Initialization

    init(baseDirectory: URL, isEnabled: Bool) {
        self.baseDirectory = baseDirectory
        self.isEnabled = isEnabled
    }

    // MARK: - Configuration

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func setBaseDirectory(_ url: URL) {
        baseDirectory = url
    }

    // MARK: - Logging

    /// Logs a full API request/response to a JSON file.
    ///
    /// Does nothing if debug logging is disabled. Errors during file writing
    /// are logged via `AppLogger` but never propagated — debug logging must never affect the main API flow.
    ///
    /// - Parameters:
    ///   - jobType: The type of job that initiated this call (e.g., "summary", "transcription", "evaluation").
    ///   - documentId: Associated document ID, if any.
    ///   - sourceId: Associated source ID, if any.
    ///   - transcriptId: Associated transcript ID, if any.
    ///   - provider: Provider identifier (e.g., "claude", "gemini").
    ///   - model: Model identifier used for the request.
    ///   - request: The outgoing `URLRequest`.
    ///   - requestBody: The request body data (captured before sending, since `httpBody` may be nil post-send).
    ///   - response: The `HTTPURLResponse` received.
    ///   - responseBody: The raw response body data.
    ///   - account: Account email that originated the request, if known.
    ///   - duration: Wall-clock duration of the request in seconds.
    func log(
        jobType: String,
        documentId: Int64?,
        sourceId: Int64?,
        transcriptId: Int64?,
        provider: String,
        model: String,
        account: String?,
        request: URLRequest,
        requestBody: Data?,
        response: HTTPURLResponse,
        responseBody: Data,
        duration: TimeInterval
    ) {
        guard isEnabled else { return }

        let entryId = UUID().uuidString
        let timestamp = Date()

        let requestHeaders = request.allHTTPHeaderFields ?? [:]
        let requestBodyString = requestBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        var responseHeaders: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            responseHeaders[String(describing: key)] = String(describing: value)
        }
        let responseBodyString = String(data: responseBody, encoding: .utf8)
            ?? "<binary data: \(responseBody.count) bytes>"

        let entry = APIDebugLogEntry(
            id: entryId,
            timestamp: timestamp,
            account: account,
            job: .init(
                type: jobType,
                documentId: documentId,
                sourceId: sourceId,
                transcriptId: transcriptId
            ),
            provider: provider,
            model: model,
            request: .init(
                url: request.url?.absoluteString ?? "unknown",
                method: request.httpMethod ?? "GET",
                headers: requestHeaders,
                body: requestBodyString
            ),
            response: .init(
                statusCode: response.statusCode,
                headers: responseHeaders,
                body: responseBodyString
            ),
            durationMs: Int(duration * 1000)
        )

        do {
            let dir = logDirectoryURL
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let dateString = Self.dateFormatter.string(from: timestamp)
            let uuidPrefix = String(entryId.prefix(8))
            let endpoint = Self.shortEndpoint(from: request.url)
            let accountSlug = Self.sanitizedAccount(account)
            var filename = "\(dateString)_\(uuidPrefix)_\(endpoint)"
            if let accountSlug {
                filename += "_\(accountSlug)"
            }
            filename += ".json"
            let fileURL = dir.appendingPathComponent(filename)

            let data = try encoder.encode(entry)
            try data.write(to: fileURL, options: .atomic)

            AppLogger.llm.debug("Debug log written: \(filename)")
        } catch {
            AppLogger.llm.error("Failed to write debug log: \(error.localizedDescription)")
        }
    }

    // MARK: - Listing & Management

    /// Lists all debug log entries, sorted by timestamp descending (newest first).
    func listEntries() -> [APIDebugLogEntry] {
        let dir = logDirectoryURL
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

            return files.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(APIDebugLogEntry.self, from: data)
            }
        } catch {
            AppLogger.llm.error("Failed to list debug logs: \(error.localizedDescription)")
            return []
        }
    }

    /// Removes all debug log files.
    func clearAll() throws {
        let dir = logDirectoryURL
        guard FileManager.default.fileExists(atPath: dir.path) else { return }

        let files = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        .filter { $0.pathExtension == "json" }

        for file in files {
            try FileManager.default.removeItem(at: file)
        }

        AppLogger.llm.info("Cleared \(files.count) debug log files")
    }

    // MARK: - Filename Helpers

    /// Extracts a short endpoint name from a URL for use in filenames.
    private static func shortEndpoint(from url: URL?) -> String {
        guard let url else { return "unknown" }
        var component = url.lastPathComponent
        // Handle Google RPC-style URLs like "/v1internal:generateContent"
        if let colonIdx = component.lastIndex(of: ":") {
            component = String(component[component.index(after: colonIdx)...])
        }
        return component.isEmpty || component == "/" ? "unknown" : component
    }

    /// Returns a filename-safe slug from an account email (local part only).
    private static func sanitizedAccount(_ account: String?) -> String? {
        guard let account, !account.isEmpty else { return nil }
        let local = account.split(separator: "@").first.map(String.init) ?? account
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let sanitized = local.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
        return sanitized.isEmpty ? nil : sanitized
    }

    /// Returns the count and total size of debug log files.
    func logDirectoryStats() -> (count: Int, totalBytes: Int64) {
        let dir = logDirectoryURL
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return (0, 0)
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )
            .filter { $0.pathExtension == "json" }

            var totalBytes: Int64 = 0
            for file in files {
                let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                totalBytes += (attrs[.size] as? Int64) ?? 0
            }

            return (files.count, totalBytes)
        } catch {
            AppLogger.llm.error("Failed to compute debug log stats: \(error.localizedDescription)")
            return (0, 0)
        }
    }
}

// MARK: - Shared Debug-Instrumented HTTP Request

/// Executes an HTTP request with optional debug logging.
///
/// Shared by all `LLMProviderStrategy` implementations to avoid code duplication.
/// Wraps `URLSession.data(for:)` to capture full request/response for debug logging.
/// Debug log writing is fire-and-forget — it never blocks the API response.
///
/// - Parameters:
///   - request: The `URLRequest` to execute.
///   - urlSession: The `URLSession` to use for the request.
///   - provider: Provider identifier for the debug log.
///   - model: Model identifier for the debug log.
///   - debugContext: Optional job context for log correlation.
///   - debugLogger: Optional debug logger. When nil, no debug logging occurs.
/// - Returns: Response data and HTTP response.
/// - Throws: `LLMError.invalidResponse` if the response is not HTTP, or network errors.
func performDebugLoggingRequest(
    _ request: URLRequest,
    urlSession: URLSession,
    provider: LLMProvider,
    model: String,
    debugContext: APIDebugContext?,
    debugLogger: APIDebugLogger?,
    account: String? = nil
) async throws -> (Data, HTTPURLResponse) {
    let requestBody = request.httpBody
    let startTime = Date()

    let (data, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw LLMError.invalidResponse(detail: "Response is not HTTP")
    }

    if let debugLogger {
        let duration = Date().timeIntervalSince(startTime)
        let providerName = provider.rawValue
        Task {
            await debugLogger.log(
                jobType: debugContext?.jobType ?? "chat",
                documentId: debugContext?.documentId,
                sourceId: debugContext?.sourceId,
                transcriptId: debugContext?.transcriptId,
                provider: providerName,
                model: model,
                account: account,
                request: request,
                requestBody: requestBody,
                response: httpResponse,
                responseBody: data,
                duration: duration
            )
        }
    }

    return (data, httpResponse)
}

//
//  HARExporter.swift
//  HiDocu
//
//  Utility for exporting API debug log entries to HAR (HTTP Archive) format.
//

import Foundation

enum HARExporter {

    /// Generates a HAR 1.2 archive from debug log entries.
    ///
    /// The output conforms to the HAR 1.2 specification and can be imported
    /// into Chrome DevTools, Charles Proxy, or any HAR-compatible tool.
    ///
    /// - Parameter entries: Debug log entries to include.
    /// - Returns: JSON data for the `.har` file.
    static func generateHAR(from entries: [APIDebugLogEntry]) throws -> Data {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let harEntries: [[String: Any]] = entries.map { entry in
            let requestHeaders: [[String: String]] = entry.request.headers
                .sorted { $0.key < $1.key }
                .map { ["name": $0.key, "value": $0.value] }

            let queryString: [[String: String]]
            if let components = URLComponents(string: entry.request.url) {
                queryString = (components.queryItems ?? []).map {
                    ["name": $0.name, "value": $0.value ?? ""]
                }
            } else {
                queryString = []
            }

            var request: [String: Any] = [
                "method": entry.request.method,
                "url": entry.request.url,
                "httpVersion": "HTTP/1.1",
                "cookies": [] as [[String: Any]],
                "headers": requestHeaders,
                "queryString": queryString,
                "headersSize": -1,
                "bodySize": entry.request.body.utf8.count
            ]

            if !entry.request.body.isEmpty {
                let mimeType = entry.request.headers
                    .first { $0.key.lowercased() == "content-type" }?.value
                    ?? "application/json"
                request["postData"] = [
                    "mimeType": mimeType,
                    "text": entry.request.body
                ] as [String: Any]
            }

            let responseHeaders: [[String: String]] = entry.response.headers
                .sorted { $0.key < $1.key }
                .map { ["name": $0.key, "value": $0.value] }

            let responseMimeType = entry.response.headers
                .first { $0.key.lowercased() == "content-type" }?.value
                ?? "application/json"

            let response: [String: Any] = [
                "status": entry.response.statusCode,
                "statusText": Self.httpReasonPhrase(for: entry.response.statusCode),
                "httpVersion": "HTTP/1.1",
                "cookies": [] as [[String: Any]],
                "headers": responseHeaders,
                "content": [
                    "size": entry.response.body.utf8.count,
                    "mimeType": responseMimeType,
                    "text": entry.response.body
                ] as [String: Any],
                "redirectURL": "",
                "headersSize": -1,
                "bodySize": entry.response.body.utf8.count
            ]

            return [
                "startedDateTime": iso8601.string(from: entry.timestamp),
                "time": entry.durationMs,
                "request": request,
                "response": response,
                "cache": [:] as [String: Any],
                "timings": [
                    "blocked": -1,
                    "dns": -1,
                    "connect": -1,
                    "ssl": -1,
                    "send": 0,
                    "wait": entry.durationMs,
                    "receive": 0
                ] as [String: Any]
            ] as [String: Any]
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": [
                    "name": "HiDocu",
                    "version": appVersion
                ],
                "entries": harEntries
            ]
        ]

        return try JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Helpers

    /// Returns the standard HTTP reason phrase for a status code.
    private static func httpReasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 301: "Moved Permanently"
        case 302: "Found"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        case 504: "Gateway Timeout"
        default: "Unknown"
        }
    }
}

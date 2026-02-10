//
//  PostmanExporter.swift
//  HiDocu
//
//  Utility for exporting API debug log entries to cURL commands and Postman collections.
//

import Foundation

enum PostmanExporter {

    // MARK: - cURL Export

    /// Generates a copy-pasteable cURL command from a debug log entry.
    ///
    /// Note: Headers are already redacted by `APIDebugLogger` at write time.
    /// The exported cURL uses the redacted values from the log file.
    static func generateCURL(from entry: APIDebugLogEntry) -> String {
        var parts: [String] = ["curl"]

        parts.append("-X \(entry.request.method)")
        parts.append("'\(entry.request.url)'")

        for (key, value) in entry.request.headers.sorted(by: { $0.key < $1.key }) {
            let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(key): \(escapedValue)'")
        }

        if !entry.request.body.isEmpty {
            let escapedBody = entry.request.body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escapedBody)'")
        }

        return parts.joined(separator: " \\\n  ")
    }

    // MARK: - Postman Collection Export

    /// Generates a Postman Collection v2.1 JSON from debug log entries.
    ///
    /// - Parameters:
    ///   - entries: Debug log entries to include in the collection.
    ///   - name: Collection name (defaults to "HiDocu Debug Export").
    /// - Returns: JSON data for the Postman collection.
    static func generatePostmanCollection(
        from entries: [APIDebugLogEntry],
        name: String = "HiDocu Debug Export"
    ) throws -> Data {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        let items: [[String: Any]] = entries.map { entry in
            let timeString = dateFormatter.string(from: entry.timestamp)

            let headers: [[String: Any]] = entry.request.headers
                .sorted { $0.key < $1.key }
                .map { ["key": $0.key, "value": $0.value, "type": "text"] }

            let urlComponents = URLComponents(string: entry.request.url)
            let host = urlComponents?.host?.split(separator: ".").map(String.init) ?? []
            let pathComponents = urlComponents?.path.split(separator: "/").map(String.init) ?? []

            var requestDict: [String: Any] = [
                "method": entry.request.method,
                "header": headers,
                "url": [
                    "raw": entry.request.url,
                    "protocol": urlComponents?.scheme ?? "https",
                    "host": host,
                    "path": pathComponents
                ] as [String: Any]
            ]

            if !entry.request.body.isEmpty {
                requestDict["body"] = [
                    "mode": "raw",
                    "raw": entry.request.body,
                    "options": [
                        "raw": ["language": "json"]
                    ]
                ] as [String: Any]
            }

            return [
                "name": "\(entry.job.type) - \(entry.provider)/\(entry.model) - \(timeString)",
                "request": requestDict
            ] as [String: Any]
        }

        let collection: [String: Any] = [
            "info": [
                "name": name,
                "_postman_id": UUID().uuidString,
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            ],
            "item": items
        ]

        return try JSONSerialization.data(
            withJSONObject: collection,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}

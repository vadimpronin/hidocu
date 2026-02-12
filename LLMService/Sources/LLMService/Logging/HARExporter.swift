import Foundation

/// Exports trace entries as HAR 1.2 format
public enum HARExporter {

    /// Convert trace entries to HAR 1.2 JSON data
    public static func export(entries: [LLMTraceEntry]) throws -> Data {
        var harEntries: [[String: Any]] = []

        for entry in entries {
            var harEntry: [String: Any] = [
                "startedDateTime": ISO8601DateFormatter().string(from: entry.timestamp),
                "time": (entry.duration ?? 0) * 1000,
                "comment": "TraceID: \(entry.traceId); Provider: \(entry.provider); Account: \(entry.accountIdentifier ?? "unknown"); Method: \(entry.method)"
            ]

            // Request
            let req = entry.request
            var reqHeaders: [[String: String]] = []
            if let headers = req.headers {
                for (key, value) in headers {
                    reqHeaders.append(["name": key, "value": value])
                }
            }
            harEntry["request"] = [
                "method": req.method ?? "POST",
                "url": req.url ?? "",
                "httpVersion": "HTTP/1.1",
                "headers": reqHeaders,
                "queryString": [],
                "cookies": [],
                "headersSize": -1,
                "bodySize": req.body?.count ?? 0,
                "postData": [
                    "mimeType": "application/json",
                    "text": req.body ?? ""
                ]
            ] as [String: Any]

            // Response
            if let resp = entry.response {
                var respHeaders: [[String: String]] = []
                if let headers = resp.headers {
                    for (key, value) in headers {
                        respHeaders.append(["name": key, "value": value])
                    }
                }
                let responseMimeType = entry.isStreaming ? "text/event-stream" : "application/json"
                harEntry["response"] = [
                    "status": resp.statusCode ?? 0,
                    "statusText": HTTPURLResponse.localizedString(forStatusCode: resp.statusCode ?? 0),
                    "httpVersion": "HTTP/1.1",
                    "headers": respHeaders,
                    "cookies": [],
                    "content": [
                        "size": resp.body?.count ?? 0,
                        "mimeType": responseMimeType,
                        "text": resp.body ?? ""
                    ],
                    "redirectURL": "",
                    "headersSize": -1,
                    "bodySize": resp.body?.count ?? 0
                ] as [String: Any]
            }

            harEntries.append(harEntry)
        }

        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "LLMService", "version": "1.0"],
                "entries": harEntries
            ]
        ]

        return try JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .sortedKeys])
    }
}

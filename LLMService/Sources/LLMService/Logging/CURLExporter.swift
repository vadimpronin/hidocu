import Foundation

/// Generates cURL commands from trace entries
public enum CURLExporter {

    /// Generate a copy-pasteable multi-line cURL command from a trace entry
    public static func generateCURL(from entry: LLMTraceEntry) -> String {
        var parts: [String] = ["curl"]

        let method = entry.request.method ?? "POST"
        parts.append("-X \(method)")

        if let url = entry.request.url {
            let escapedURL = url.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("'\(escapedURL)'")
        }

        if let headers = entry.request.headers {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-H '\(key): \(escapedValue)'")
            }
        }

        if let body = entry.request.body, !body.isEmpty {
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escapedBody)'")
        }

        return parts.joined(separator: " \\\n  ")
    }
}

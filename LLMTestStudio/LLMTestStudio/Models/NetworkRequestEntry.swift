import Foundation
import LLMService
import SwiftUI

/// View-friendly wrapper around `LLMTraceEntry` with computed display properties
struct NetworkRequestEntry: Identifiable {
    let trace: LLMTraceEntry

    var id: String { trace.id }

    // MARK: - Display Properties

    var shortURL: String {
        guard let urlString = trace.request.url,
              let components = URLComponents(string: urlString) else {
            return trace.request.url ?? "—"
        }
        return components.path
    }

    var fullURL: String {
        trace.request.url ?? "—"
    }

    var httpMethod: String {
        trace.request.method ?? "POST"
    }

    var statusCode: Int? {
        trace.response?.statusCode
    }

    var statusText: String {
        guard let code = statusCode else {
            return trace.error != nil ? "ERR" : "…"
        }
        return "\(code)"
    }

    var statusColor: Color {
        if trace.error != nil { return .red }
        guard let code = statusCode else { return .secondary }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        default: return .red
        }
    }

    var durationText: String {
        guard let duration = trace.duration else { return "—" }
        if duration < 1 {
            return "\(Int(duration * 1000))ms"
        }
        return String(format: "%.2fs", duration)
    }

    var provider: String {
        trace.provider
    }

    var typeText: String {
        var text = trace.method
        if trace.isStreaming {
            text += " ⇶"
        }
        return text
    }

    var timestamp: Date {
        trace.timestamp
    }

    // MARK: - Formatted Bodies

    var formattedRequestBody: String {
        formatBody(trace.request.body)
    }

    var formattedResponseBody: String {
        formatBody(trace.response?.body)
    }

    var requestHeaders: [(key: String, value: String)] {
        sortedHeaders(trace.request.headers)
    }

    var responseHeaders: [(key: String, value: String)] {
        sortedHeaders(trace.response?.headers)
    }

    // MARK: - Private

    private func formatBody(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return "(empty)" }
        guard let data = body.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return body
        }
        return prettyString
    }

    private func sortedHeaders(_ headers: [String: String]?) -> [(key: String, value: String)] {
        guard let headers else { return [] }
        return headers.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (key: $0.key, value: $0.value) }
    }
}

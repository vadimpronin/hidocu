//
//  SSEParser.swift
//  HiDocu
//
//  Server-Sent Events (SSE) parser for streaming LLM responses.
//

import Foundation

/// A single Server-Sent Event.
struct SSEEvent: Sendable {
    let event: String?
    let data: String
    let id: String?
}

/// Parser for Server-Sent Events (SSE) streams per W3C specification.
///
/// Supports:
/// - Multi-line data fields (joined with newlines)
/// - Event types via `event:` field
/// - Event IDs via `id:` field
/// - Comments (lines starting with `:`)
/// - `[DONE]` sentinel for stream completion
enum SSEParser {
    /// Parses complete SSE data into individual events.
    ///
    /// - Parameter data: Complete SSE response data
    /// - Returns: Array of parsed events
    static func parse(from data: Data) -> [SSEEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        var events: [SSEEvent] = []
        var currentEvent: String?
        var currentData: [String] = []
        var currentId: String?

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            // Empty line signals end of event
            if line.isEmpty {
                if !currentData.isEmpty {
                    let data = currentData.joined(separator: "\n")
                    events.append(SSEEvent(event: currentEvent, data: data, id: currentId))
                    currentData = []
                    currentEvent = nil
                    currentId = nil
                }
                continue
            }

            // Comment line (ignore)
            if line.hasPrefix(":") {
                continue
            }

            // Parse field
            if let colonIndex = line.firstIndex(of: ":") {
                let field = String(line[..<colonIndex])
                var value = String(line[line.index(after: colonIndex)...])

                // Remove leading space from value if present
                if value.hasPrefix(" ") {
                    value = String(value.dropFirst())
                }

                switch field {
                case "event":
                    currentEvent = value
                case "data":
                    currentData.append(value)
                case "id":
                    currentId = value
                default:
                    break
                }
            }
        }

        // Handle final event if no trailing newline
        if !currentData.isEmpty {
            let data = currentData.joined(separator: "\n")
            events.append(SSEEvent(event: currentEvent, data: data, id: currentId))
        }

        return events
    }

    /// Streams SSE events from a URL request using URLSession.
    ///
    /// - Parameters:
    ///   - urlSession: URLSession instance to use
    ///   - request: URLRequest configured for SSE endpoint
    /// - Returns: AsyncThrowingStream of SSE events
    static func stream(
        from urlSession: URLSession,
        request: URLRequest
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = urlSession.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: LLMError.invalidResponse(detail: "Not an HTTP response"))
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                    continuation.finish(throwing: LLMError.invalidResponse(
                        detail: "HTTP \(httpResponse.statusCode): \(message)"
                    ))
                    return
                }

                guard let data = data else {
                    continuation.finish()
                    return
                }

                let events = parse(from: data)
                for event in events {
                    // Check for [DONE] sentinel
                    if event.data == "[DONE]" {
                        continuation.finish()
                        return
                    }

                    continuation.yield(event)
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }

            task.resume()
        }
    }

    /// Streams SSE events from URLSession bytes asynchronously.
    ///
    /// - Parameters:
    ///   - urlSession: URLSession instance to use
    ///   - request: URLRequest configured for SSE endpoint
    /// - Returns: AsyncThrowingStream of SSE events
    static func streamBytes(
        from urlSession: URLSession,
        request: URLRequest
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await urlSession.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMError.invalidResponse(detail: "Not an HTTP response")
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw LLMError.invalidResponse(
                            detail: "HTTP \(httpResponse.statusCode)"
                        )
                    }

                    var buffer = ""
                    var currentEvent: String?
                    var currentData: [String] = []
                    var currentId: String?

                    for try await byte in bytes {
                        guard let char = String(bytes: [byte], encoding: .utf8) else {
                            continue
                        }

                        buffer.append(char)

                        // Check for newline
                        if char == "\n" {
                            let line = buffer.trimmingCharacters(in: .newlines)
                            buffer = ""

                            // Empty line signals end of event
                            if line.isEmpty {
                                if !currentData.isEmpty {
                                    let data = currentData.joined(separator: "\n")

                                    // Check for [DONE] sentinel
                                    if data == "[DONE]" {
                                        continuation.finish()
                                        return
                                    }

                                    let event = SSEEvent(event: currentEvent, data: data, id: currentId)
                                    continuation.yield(event)

                                    currentData = []
                                    currentEvent = nil
                                    currentId = nil
                                }
                                continue
                            }

                            // Comment line (ignore)
                            if line.hasPrefix(":") {
                                continue
                            }

                            // Parse field
                            if let colonIndex = line.firstIndex(of: ":") {
                                let field = String(line[..<colonIndex])
                                var value = String(line[line.index(after: colonIndex)...])

                                // Remove leading space from value if present
                                if value.hasPrefix(" ") {
                                    value = String(value.dropFirst())
                                }

                                switch field {
                                case "event":
                                    currentEvent = value
                                case "data":
                                    currentData.append(value)
                                case "id":
                                    currentId = value
                                default:
                                    break
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

import Foundation

/// Parser for Claude's SSE streaming format.
///
/// Claude SSE events follow the pattern:
/// ```
/// event: {type}
/// data: {json}
///
/// ```
///
/// This parser is stateful — it tracks the current message id, model, and
/// active content block so that each emitted `LLMChatChunk` carries the
/// correct metadata.
final class ClaudeStreamParser: @unchecked Sendable {

    private var responseId: String = ""
    private var model: String = ""
    private var currentBlockType: String = ""
    private var currentBlockIndex: Int = 0
    private var currentToolId: String = ""
    private var currentToolName: String = ""
    private var inputTokens: Int = 0
    private var pendingEventType: String = ""

    /// Parse a single SSE event given its event type and JSON data payload.
    func parseSSEEvent(eventType: String, data: Data) -> [LLMChatChunk] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        switch eventType {
        case "message_start":
            if let message = json["message"] as? [String: Any] {
                responseId = message["id"] as? String ?? ""
                model = message["model"] as? String ?? ""
                if let usage = message["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? 0
                }
            }
            return []

        case "content_block_start":
            if let block = json["content_block"] as? [String: Any] {
                let type = block["type"] as? String ?? ""
                currentBlockType = type
                currentBlockIndex = json["index"] as? Int ?? 0

                if type == "tool_use" {
                    currentToolId = block["id"] as? String ?? ""
                    currentToolName = block["name"] as? String ?? ""
                }
            }
            return []

        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any],
                  let deltaType = delta["type"] as? String else {
                return []
            }

            switch deltaType {
            case "text_delta":
                let text = delta["text"] as? String ?? ""
                return [LLMChatChunk(id: responseId, partType: .text, delta: text)]

            case "thinking_delta":
                let thinking = delta["thinking"] as? String ?? ""
                return [LLMChatChunk(id: responseId, partType: .thinking, delta: thinking)]

            case "input_json_delta":
                let partialJson = delta["partial_json"] as? String ?? ""
                return [LLMChatChunk(
                    id: responseId,
                    partType: .toolCall(id: currentToolId, function: currentToolName),
                    delta: partialJson
                )]

            default:
                return []
            }

        case "content_block_stop":
            currentBlockType = ""
            return []

        case "message_delta":
            // message_delta carries final usage and stop_reason.
            if let usage = json["usage"] as? [String: Any] {
                let outputTokens = usage["output_tokens"] as? Int ?? 0
                return [LLMChatChunk(
                    id: responseId,
                    partType: .text,
                    delta: "",
                    usage: LLMUsage(inputTokens: inputTokens, outputTokens: outputTokens)
                )]
            }
            return []

        case "message_stop":
            return []

        case "ping":
            return []

        case "error":
            // The API may send an error event mid-stream.
            return []

        default:
            return []
        }
    }

    /// Parse a single SSE line from the byte-level stream reader.
    ///
    /// Tracks the pending event type across calls so that `event:` and `data:`
    /// lines arriving as separate calls are properly paired.
    func parseStreamLine(_ line: String) -> [LLMChatChunk] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("event: ") {
            pendingEventType = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            return []
        } else if trimmed.hasPrefix("data: ") {
            let dataStr = String(trimmed.dropFirst(6))
            let eventType = pendingEventType
            pendingEventType = ""
            if let data = dataStr.data(using: .utf8) {
                return parseSSEEvent(eventType: eventType, data: data)
            }
        }
        return []
    }

    /// Parse raw SSE text that may contain one or more event+data pairs.
    ///
    /// Format:
    /// ```
    /// event: {type}
    /// data: {json}
    ///
    /// ```
    func parseSSEText(_ text: String) -> [LLMChatChunk] {
        var chunks: [LLMChatChunk] = []
        var currentEvent = ""

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                let dataStr = String(line.dropFirst(6))
                if let data = dataStr.data(using: .utf8) {
                    chunks.append(contentsOf: parseSSEEvent(eventType: currentEvent, data: data))
                }
                currentEvent = ""
            }
            // Empty lines and other prefixes (e.g. comments starting with ':') are ignored.
        }

        return chunks
    }
}

import Foundation

enum ClaudeResponseParser {

    /// Parse a non-streaming Claude Messages API response into LLMResponse.
    static func parseResponse(data: Data, traceId: String) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMServiceError(traceId: traceId, message: "Invalid JSON response")
        }

        // Check for error response.
        if let errorInfo = json["error"] as? [String: Any] {
            let message = errorInfo["message"] as? String ?? "Unknown error"
            let type = errorInfo["type"] as? String ?? "api_error"
            throw LLMServiceError(
                traceId: traceId,
                message: "\(type): \(message)"
            )
        }

        let id = json["id"] as? String ?? ""
        let model = json["model"] as? String ?? ""

        var parts: [LLMResponsePart] = []

        if let content = json["content"] as? [[String: Any]] {
            for block in content {
                guard let type = block["type"] as? String else { continue }
                switch type {
                case "text":
                    if let text = block["text"] as? String {
                        parts.append(.text(text))
                    }
                case "thinking":
                    if let thinking = block["thinking"] as? String {
                        parts.append(.thinking(thinking))
                    }
                case "tool_use":
                    let toolId = block["id"] as? String ?? ""
                    let name = block["name"] as? String ?? ""
                    let input = block["input"] ?? [:] as [String: Any]
                    if let argsData = try? JSONSerialization.data(withJSONObject: input),
                       let argsString = String(data: argsData, encoding: .utf8) {
                        parts.append(.toolCall(id: toolId, function: name, arguments: argsString))
                    } else {
                        parts.append(.toolCall(id: toolId, function: name, arguments: "{}"))
                    }
                default:
                    break
                }
            }
        }

        var usage: LLMUsage?
        if let usageDict = json["usage"] as? [String: Any] {
            let inputTokens = usageDict["input_tokens"] as? Int ?? 0
            let outputTokens = usageDict["output_tokens"] as? Int ?? 0
            usage = LLMUsage(inputTokens: inputTokens, outputTokens: outputTokens)
        }

        return LLMResponse(
            id: id,
            model: model,
            traceId: traceId,
            content: parts,
            usage: usage
        )
    }
}

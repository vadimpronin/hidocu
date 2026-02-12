import Foundation

enum AntigravityResponseParser {

    /// Parse a non-streaming Antigravity API response into LLMResponse.
    /// The response JSON is expected to have a top-level "response" key containing
    /// candidates, usageMetadata, responseId, and modelVersion.
    static func parseResponse(data: Data, traceId: String) throws -> LLMResponse {
        guard let topLevel = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMServiceError(traceId: traceId, message: "Invalid JSON response")
        }

        // Support both wrapped ("response": {...}) and unwrapped formats
        let json = (topLevel["response"] as? [String: Any]) ?? topLevel

        let responseId = json["responseId"] as? String ?? ""
        let modelVersion = json["modelVersion"] as? String ?? ""

        let content = parseParts(from: json)
        let usage = parseUsage(from: json)

        return LLMResponse(
            id: responseId,
            model: modelVersion,
            traceId: traceId,
            content: content,
            usage: usage
        )
    }

    // MARK: - Private

    private static func parseParts(from json: [String: Any]) -> [LLMResponsePart] {
        guard
            let candidates = json["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            return []
        }

        var result: [LLMResponsePart] = []

        for part in parts {
            if let functionCall = part["functionCall"] as? [String: Any],
               let name = functionCall["name"] as? String
            {
                let callId = functionCall["id"] as? String ?? UUID().uuidString
                let args = functionCall["args"] as? [String: Any] ?? [:]
                let argsJSON: String
                if let argsData = try? JSONSerialization.data(withJSONObject: args),
                   let argsStr = String(data: argsData, encoding: .utf8)
                {
                    argsJSON = argsStr
                } else {
                    argsJSON = "{}"
                }
                result.append(.toolCall(id: callId, function: name, arguments: argsJSON))
            } else if let inlineData = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any]) {
                let base64String = inlineData["data"] as? String ?? ""
                guard !base64String.isEmpty,
                      let decoded = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters)
                else { continue }
                let mimeType = (inlineData["mimeType"] as? String)
                    ?? (inlineData["mime_type"] as? String)
                    ?? "image/png"
                result.append(.inlineData(decoded, mimeType: mimeType))
            } else if let text = part["text"] as? String {
                let isThought = part["thought"] as? Bool ?? false
                if isThought {
                    result.append(.thinking(text))
                } else {
                    result.append(.text(text))
                }
            }
        }

        return result
    }

    private static func parseUsage(from json: [String: Any]) -> LLMUsage? {
        guard let metadata = json["usageMetadata"] as? [String: Any] else {
            return nil
        }

        let promptTokens = metadata["promptTokenCount"] as? Int ?? 0
        let candidatesTokens = metadata["candidatesTokenCount"] as? Int ?? 0
        let thoughtsTokens = metadata["thoughtsTokenCount"] as? Int ?? 0

        return LLMUsage(
            inputTokens: promptTokens,
            outputTokens: candidatesTokens + thoughtsTokens
        )
    }
}

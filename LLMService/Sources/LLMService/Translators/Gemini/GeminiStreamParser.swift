import Foundation

/// State machine for parsing Gemini SSE stream into LLMChatChunk sequence.
///
/// Each SSE event contains a JSON object with incremental response data.
/// The parser tracks the current content block type (text/thinking/function)
/// and emits properly typed LLMChatChunk values on each state transition.
final class GeminiStreamParser: @unchecked Sendable {

    // MARK: - State

    private enum ResponseState {
        case none
        case text
        case thinking
        case function
    }

    private var state: ResponseState = .none
    private var blockIndex: Int = 0
    private var responseId: String = ""
    private var modelVersion: String = ""

    // Thought signature tracking
    private var currentThinkingText: String = ""
    private var currentModelVersion: String = ""

    // Usage tracking — emit final chunk when both are present
    private var hasFinishReason: Bool = false
    private var finishReason: String = ""
    private var hasUsageMetadata: Bool = false
    private var promptTokenCount: Int = 0
    private var candidatesTokenCount: Int = 0
    private var thoughtsTokenCount: Int = 0
    private var totalTokenCount: Int = 0
    private var hasSentFinalEvents: Bool = false
    private var hasToolUse: Bool = false

    // MARK: - Public API

    /// Parse a single SSE line (e.g. `"data: {json}"` or `"data: [DONE]"`).
    /// Returns an array of chunks to emit.
    func parseSSELine(_ line: String) -> [LLMChatChunk] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data: ") else { return [] }

        let payload = String(trimmed.dropFirst(6))
        if payload == "[DONE]" {
            return finalize()
        }

        guard let data = payload.data(using: .utf8) else { return [] }
        return parseSSEData(data)
    }

    /// Parse the JSON payload from a single SSE data event.
    func parseSSEData(_ jsonData: Data) -> [LLMChatChunk] {
        guard let topLevel = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return []
        }

        // Support both wrapped and unwrapped formats
        let json = (topLevel["response"] as? [String: Any]) ?? topLevel

        // Capture response metadata
        if let rid = json["responseId"] as? String, !rid.isEmpty {
            responseId = rid
        }
        if let mv = json["modelVersion"] as? String, !mv.isEmpty {
            modelVersion = mv
        }

        var chunks: [LLMChatChunk] = []

        // Process parts
        if let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]]
        {
            for part in parts {
                let partChunks = processPart(part)
                chunks.append(contentsOf: partChunks)
            }

            // Track finish reason
            if let fr = firstCandidate["finishReason"] as? String, !fr.isEmpty {
                hasFinishReason = true
                finishReason = fr
            }
        }

        // Track usage metadata
        if let metadata = json["usageMetadata"] as? [String: Any] {
            hasUsageMetadata = true
            promptTokenCount = metadata["promptTokenCount"] as? Int ?? 0
            candidatesTokenCount = metadata["candidatesTokenCount"] as? Int ?? 0
            thoughtsTokenCount = metadata["thoughtsTokenCount"] as? Int ?? 0
            totalTokenCount = metadata["totalTokenCount"] as? Int ?? 0
        }

        // Emit final usage chunk when both finish reason and usage are available
        if hasFinishReason && hasUsageMetadata && !hasSentFinalEvents {
            hasSentFinalEvents = true
            let usage = LLMUsage(
                inputTokens: promptTokenCount,
                outputTokens: candidatesTokenCount + thoughtsTokenCount
            )
            chunks.append(LLMChatChunk(
                id: responseId,
                partType: .text,
                delta: "",
                usage: usage
            ))
        }

        return chunks
    }

    /// Finalize the stream — called on `[DONE]`. Emits any remaining events.
    func finalize() -> [LLMChatChunk] {
        var chunks: [LLMChatChunk] = []

        // Emit final usage chunk if not yet sent
        if !hasSentFinalEvents && hasUsageMetadata {
            hasSentFinalEvents = true
            let usage = LLMUsage(
                inputTokens: promptTokenCount,
                outputTokens: candidatesTokenCount + thoughtsTokenCount
            )
            chunks.append(LLMChatChunk(
                id: responseId,
                partType: .text,
                delta: "",
                usage: usage
            ))
        }

        state = .none
        return chunks
    }

    // MARK: - Private

    private func processPart(_ part: [String: Any]) -> [LLMChatChunk] {
        // Function call
        if let functionCall = part["functionCall"] as? [String: Any],
           let name = functionCall["name"] as? String
        {
            return handleFunctionCall(name: name, args: functionCall["args"], id: functionCall["id"] as? String)
        }

        // Inline data (e.g., images) — emitted atomically as a single chunk
        if let inlineData = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any]) {
            return handleInlineData(inlineData)
        }

        // Text (possibly thinking)
        if let text = part["text"] as? String {
            let isThought = part["thought"] as? Bool ?? false
            if isThought {
                currentThinkingText += text
                // Cache thought signature if present
                if let signature = part["thoughtSignature"] as? String,
                   ThoughtSignatureCache.isValid(signature) {
                    let model = currentModelVersion.isEmpty ? modelVersion : currentModelVersion
                    let thinkingSnapshot = currentThinkingText
                    Task {
                        await ThoughtSignatureCache.shared.cache(
                            modelName: model,
                            thinkingText: thinkingSnapshot,
                            signature: signature
                        )
                    }
                }
                return handleThinking(text: text)
            } else {
                // Reset thinking buffer when transitioning away from thinking
                if state == .thinking {
                    currentThinkingText = ""
                }
                return handleText(text: text)
            }
        }

        return []
    }

    private func handleThinking(text: String) -> [LLMChatChunk] {
        switch state {
        case .thinking:
            // Continue thinking block — just emit delta
            return [LLMChatChunk(id: responseId, partType: .thinking, delta: text)]

        case .none, .text, .function:
            // Transition to thinking
            state = .thinking
            blockIndex += 1
            return [LLMChatChunk(id: responseId, partType: .thinking, delta: text)]
        }
    }

    private func handleText(text: String) -> [LLMChatChunk] {
        switch state {
        case .text:
            // Continue text block — just emit delta
            return [LLMChatChunk(id: responseId, partType: .text, delta: text)]

        case .none, .thinking, .function:
            // Transition to text
            state = .text
            blockIndex += 1
            return [LLMChatChunk(id: responseId, partType: .text, delta: text)]
        }
    }

    private func handleInlineData(_ inlineData: [String: Any]) -> [LLMChatChunk] {
        let base64String = inlineData["data"] as? String ?? ""
        guard !base64String.isEmpty else { return [] }

        // Support both camelCase and snake_case keys
        let mimeType = (inlineData["mimeType"] as? String)
            ?? (inlineData["mime_type"] as? String)
            ?? "image/png"

        state = .none
        blockIndex += 1
        return [LLMChatChunk(
            id: responseId,
            partType: .inlineData(mimeType: mimeType),
            delta: base64String
        )]
    }

    private func handleFunctionCall(name: String, args: Any?, id: String?) -> [LLMChatChunk] {
        state = .function
        blockIndex += 1
        hasToolUse = true

        let callId = id ?? UUID().uuidString

        // Serialize args to JSON string
        let argsJSON: String
        if let argsObj = args,
           let argsData = try? JSONSerialization.data(withJSONObject: argsObj),
           let argsStr = String(data: argsData, encoding: .utf8)
        {
            argsJSON = argsStr
        } else {
            argsJSON = "{}"
        }

        return [LLMChatChunk(
            id: responseId,
            partType: .toolCall(id: callId, function: name),
            delta: argsJSON
        )]
    }
}

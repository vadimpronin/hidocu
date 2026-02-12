import Foundation

// MARK: - Stream Aggregation

extension LLMService {

    internal func aggregateStreamResponse(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        idempotencyKey: String?,
        traceId: String
    ) async throws -> LLMResponse {
        let stream = chatStreamInternal(
            modelId: modelId,
            messages: messages,
            thinking: thinking,
            idempotencyKey: idempotencyKey,
            traceId: traceId,
            method: "chat"
        )

        var responseId = ""
        var parts: [LLMResponsePart] = []
        var currentPartType: String = ""
        var currentText = ""
        var currentToolId = ""
        var currentToolName = ""
        var lastUsage: LLMUsage?

        for try await chunk in stream {
            responseId = chunk.id
            if let usage = chunk.usage {
                lastUsage = usage
            }

            switch chunk.partType {
            case .text:
                if currentPartType != "text" {
                    flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)
                    currentPartType = "text"
                }
                currentText += chunk.delta

            case .thinking:
                if currentPartType != "thinking" {
                    flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)
                    currentPartType = "thinking"
                }
                currentText += chunk.delta

            case .toolCall(let id, let function):
                let key = "tool:\(id):\(function)"
                if currentPartType != key {
                    flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)
                    currentPartType = key
                    currentToolId = id
                    currentToolName = function
                }
                currentText += chunk.delta

            case .inlineData(let mimeType):
                // inlineData arrives atomically in a single SSE event (per CLIProxyAPI reference),
                // decode immediately without accumulation
                flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)
                if let decoded = Data(base64Encoded: chunk.delta, options: .ignoreUnknownCharacters) {
                    parts.append(.inlineData(decoded, mimeType: mimeType))
                } else {
                    llmServiceLogger.warning("[\(traceId)] aggregateStreamResponse: failed to decode base64 inlineData (\(chunk.delta.count) chars, mimeType=\(mimeType))")
                }
            }
        }

        flushPart(&parts, type: &currentPartType, text: &currentText, toolId: &currentToolId, toolName: &currentToolName)

        return LLMResponse(
            id: responseId,
            model: modelId,
            traceId: traceId,
            content: parts,
            usage: lastUsage
        )
    }

    internal func flushPart(
        _ parts: inout [LLMResponsePart],
        type: inout String,
        text: inout String,
        toolId: inout String,
        toolName: inout String
    ) {
        guard !type.isEmpty else { return }
        switch type {
        case "text":
            if !text.isEmpty { parts.append(.text(text)) }
        case "thinking":
            if !text.isEmpty { parts.append(.thinking(text)) }
        default:
            if type.hasPrefix("tool:") {
                parts.append(.toolCall(id: toolId, function: toolName, arguments: text))
            }
        }
        text = ""
        type = ""
        toolId = ""
        toolName = ""
    }
}

import CryptoKit
import Foundation

enum AntigravityRequestBuilder {

    /// Build an Antigravity API request from LLMMessage array.
    /// Returns a fully wrapped Antigravity envelope with the inner Google Cloud request.
    /// Does NOT include SafetySettings (Antigravity does not support them).
    static func buildRequest(
        modelName: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        projectId: String,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        maxOutputTokens: Int? = nil,
        tools: [[String: Any]]? = nil
    ) -> [String: Any] {
        // 1. Build inner request body (Gemini format, no safety settings)
        var requestBody = buildInnerRequest(
            messages: messages,
            thinking: thinking,
            temperature: temperature,
            topP: topP,
            topK: topK,
            maxOutputTokens: maxOutputTokens,
            tools: tools
        )

        // 2. Add session ID derived from first user message
        requestBody["sessionId"] = generateSessionId(messages: messages)

        // 3. For Claude models, set toolConfig.functionCallingConfig.mode = "VALIDATED"
        if isClaudeModel(modelName) {
            requestBody["toolConfig"] = [
                "functionCallingConfig": [
                    "mode": "VALIDATED"
                ]
            ]
        }

        // 4. Wrap with Antigravity envelope
        return [
            "model": modelName,
            "userAgent": "antigravity",
            "requestType": "agent",
            "project": projectId,
            "requestId": "agent-\(UUID().uuidString)",
            "request": requestBody,
        ]
    }

    // MARK: - Inner Request Building

    private static func buildInnerRequest(
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        temperature: Double?,
        topP: Double?,
        topK: Int?,
        maxOutputTokens: Int?,
        tools: [[String: Any]]?
    ) -> [String: Any] {
        var request: [String: Any] = [:]
        var systemParts: [[String: Any]] = []
        var contents: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .system:
                for content in message.content {
                    if case .text(let str) = content, !str.isEmpty {
                        systemParts.append(["text": str])
                    }
                }

            case .user, .assistant, .tool:
                let googleRole = mapRole(message.role)
                let parts = buildParts(from: message.content)
                if !parts.isEmpty {
                    contents.append(["role": googleRole, "parts": parts])
                }
            }
        }

        if !systemParts.isEmpty {
            request["systemInstruction"] = ["role": "user", "parts": systemParts]
        }

        if !contents.isEmpty {
            request["contents"] = contents
        }

        // Generation config
        var genConfig: [String: Any] = [:]
        if let temp = temperature { genConfig["temperature"] = temp }
        if let tp = topP { genConfig["topP"] = tp }
        if let tk = topK { genConfig["topK"] = tk }
        if let max = maxOutputTokens { genConfig["maxOutputTokens"] = max }

        if let thinking = thinking {
            switch thinking.type {
            case .enabled(let budget):
                genConfig["thinkingConfig"] = [
                    "thinkingBudget": budget,
                    "includeThoughts": true,
                ] as [String: Any]
            case .adaptive:
                genConfig["thinkingConfig"] = [
                    "thinkingLevel": "high",
                    "includeThoughts": true,
                ] as [String: Any]
            case .disabled:
                break
            }
        }

        if !genConfig.isEmpty {
            request["generationConfig"] = genConfig
        }

        // Tools
        if let tools = tools, !tools.isEmpty {
            request["tools"] = [["functionDeclarations": tools]]
        }

        // NOTE: No safetySettings — Antigravity does not support them

        return request
    }

    // MARK: - Session ID Generation

    /// Generate session ID: SHA-256 of first user message text, interpreted as Int64, prefixed with "-"
    private static func generateSessionId(messages: [LLMMessage]) -> String {
        let firstUserText = messages
            .first(where: { $0.role == .user })?
            .content
            .compactMap { content -> String? in
                if case .text(let text) = content { return text }
                return nil
            }
            .joined() ?? ""

        guard !firstUserText.isEmpty else {
            return "-\(Int64.random(in: 1_000_000_000_000_000_000...9_000_000_000_000_000_000))"
        }

        let hash = SHA256.hash(data: Data(firstUserText.utf8))
        let hashBytes = Array(hash)

        // Interpret first 8 bytes as big-endian Int64 (mask sign bit to keep positive)
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(hashBytes[i])
        }
        let signedValue = Int64(bitPattern: value & 0x7FFFFFFFFFFFFFFF)

        return "-\(signedValue)"
    }

    // MARK: - Helpers

    private static func isClaudeModel(_ modelId: String) -> Bool {
        modelId.lowercased().contains("claude")
    }

    private static func mapRole(_ role: LLMMessage.LLMChatRole) -> String {
        switch role {
        case .assistant: return "model"
        case .tool: return "user"
        case .user: return "user"
        case .system: return "user"
        }
    }

    private static func buildParts(from content: [LLMContent]) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        for item in content {
            if let part = convertContent(item) {
                parts.append(part)
            }
        }
        return parts
    }

    private static func convertContent(_ content: LLMContent) -> [String: Any]? {
        switch content {
        case .text(let str):
            guard !str.isEmpty else { return nil }
            return ["text": str]

        case .thinking(let str, let signature):
            guard !str.isEmpty else { return nil }
            var part: [String: Any] = ["text": str, "thought": true]
            if let sig = signature, !sig.isEmpty {
                part["thoughtSignature"] = sig
            }
            return part

        case .fileContent(let data, let mimeType, _):
            return [
                "inlineData": [
                    "mime_type": mimeType,
                    "data": data.base64EncodedString(),
                ] as [String: Any]
            ]

        case .file(let url):
            guard let processed = try? ContentProcessor.processContent(.file(url)) else {
                return nil
            }
            switch processed {
            case .text(let str):
                guard !str.isEmpty else { return nil }
                return ["text": str]
            case .binary(let data, let mimeType, _):
                return [
                    "inlineData": [
                        "mime_type": mimeType,
                        "data": data.base64EncodedString(),
                    ] as [String: Any]
                ]
            }
        }
    }
}

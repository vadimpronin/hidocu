import Foundation

enum GeminiRequestBuilder {

    /// Build a Gemini API request from LLMMessage array.
    /// Returns a JSON dictionary with "model" and "request" keys.
    /// Includes SafetySettings (required for Gemini).
    static func buildRequest(
        modelName: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        maxOutputTokens: Int? = nil,
        tools: [[String: Any]]? = nil
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

        // Safety settings (Gemini requires them)
        request["safetySettings"] = Self.defaultSafetySettings()

        return [
            "model": modelName,
            "request": request,
        ]
    }

    // MARK: - Safety Settings

    private static func defaultSafetySettings() -> [[String: String]] {
        [
            ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "OFF"],
            ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "OFF"],
            ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "OFF"],
            ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "OFF"],
            ["category": "HARM_CATEGORY_CIVIC_INTEGRITY", "threshold": "BLOCK_NONE"],
        ]
    }

    // MARK: - Private

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

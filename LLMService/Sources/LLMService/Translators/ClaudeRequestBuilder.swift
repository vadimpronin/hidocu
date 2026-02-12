import Foundation

enum ClaudeRequestBuilder {

    /// Build an Anthropic Messages API request from LLMMessage array.
    static func buildRequest(
        modelId: String,
        messages: [LLMMessage],
        thinking: ThinkingConfig?,
        stream: Bool,
        maxTokens: Int = 16384,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        tools: [[String: Any]]? = nil
    ) -> [String: Any] {
        var request: [String: Any] = [
            "model": modelId,
            "max_tokens": maxTokens,
            "stream": stream
        ]

        // Separate system messages from chat messages.
        var systemParts: [[String: Any]] = []
        var chatMessages: [[String: Any]] = []

        for message in messages {
            switch message.role {
            case .system:
                for content in message.content {
                    if case .text(let text) = content {
                        systemParts.append(["type": "text", "text": text])
                    }
                }

            case .user, .assistant:
                let contentArray = buildContentArray(message.content)
                if !contentArray.isEmpty {
                    chatMessages.append([
                        "role": message.role.rawValue,
                        "content": contentArray
                    ])
                }

            case .tool:
                // Claude expects tool results as role "user" with tool_result content blocks.
                // Each text content in a tool message is treated as a tool_result.
                // If there is no tool call id available, fall back to a plain user message.
                let contentArray = buildToolResultContent(message.content)
                if !contentArray.isEmpty {
                    chatMessages.append([
                        "role": "user",
                        "content": contentArray
                    ])
                }
            }
        }

        if !systemParts.isEmpty {
            request["system"] = systemParts
        }
        if !chatMessages.isEmpty {
            request["messages"] = chatMessages
        }

        // Thinking configuration.
        if let thinking = thinking {
            switch thinking.type {
            case .enabled(let budgetTokens):
                request["thinking"] = [
                    "type": "enabled",
                    "budget_tokens": budgetTokens
                ]
            case .adaptive:
                request["thinking"] = ["type": "adaptive"]
            case .disabled:
                break
            }
        }

        // Generation parameters (omitted when nil to use API defaults).
        if let temperature = temperature { request["temperature"] = temperature }
        if let topP = topP { request["top_p"] = topP }
        if let topK = topK { request["top_k"] = topK }

        // Tools
        if let tools = tools, !tools.isEmpty {
            request["tools"] = tools
        }

        ensureCacheControl(&request)

        return request
    }

    /// Serialize the request dictionary to JSON Data.
    static func serializeRequest(_ request: [String: Any]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    }

    // MARK: - Private Helpers

    private static func buildContentArray(_ contents: [LLMContent]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for content in contents {
            switch content {
            case .text(let text):
                result.append(["type": "text", "text": text])

            case .thinking(let text, let signature):
                var block: [String: Any] = ["type": "thinking", "thinking": text]
                if let sig = signature, !sig.isEmpty {
                    block["signature"] = sig
                }
                result.append(block)

            case .fileContent(let data, let mimeType, _):
                if mimeType.hasPrefix("image/") {
                    result.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": mimeType,
                            "data": data.base64EncodedString()
                        ] as [String: Any]
                    ])
                } else {
                    // Non-image binary: include as text if possible.
                    let text = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
                    result.append(["type": "text", "text": text])
                }

            case .file(let url):
                guard let processed = try? ContentProcessor.processContent(content) else {
                    // Fallback: include the file path as text.
                    result.append(["type": "text", "text": "[File: \(url.lastPathComponent)]"])
                    continue
                }
                switch processed {
                case .text(let text):
                    result.append(["type": "text", "text": text])
                case .binary(let data, let mime, _):
                    if mime.hasPrefix("image/") {
                        result.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": mime,
                                "data": data.base64EncodedString()
                            ] as [String: Any]
                        ])
                    } else {
                        let text = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
                        result.append(["type": "text", "text": text])
                    }
                }
            }
        }
        return result
    }

    private static func buildToolResultContent(_ contents: [LLMContent]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for content in contents {
            if case .text(let text) = content {
                result.append(["type": "text", "text": text])
            }
        }
        return result
    }

    // MARK: - Prompt Caching

    /// Inject up to 3 `cache_control` breakpoints into the request for cost optimization.
    ///
    /// Breakpoints are placed on: (1) last tool, (2) last system part, (3) second-to-last
    /// user message's last content block. If any `cache_control` key already exists in the
    /// request, the method is a no-op.
    static func ensureCacheControl(_ request: inout [String: Any]) {
        // If any cache_control already present, skip entirely.
        if countCacheControls(request) > 0 { return }

        let ephemeral: [String: Any] = ["type": "ephemeral"]

        // 1. Tools breakpoint: add to last tool
        if var tools = request["tools"] as? [[String: Any]], !tools.isEmpty {
            var lastTool = tools[tools.count - 1]
            lastTool["cache_control"] = ephemeral
            tools[tools.count - 1] = lastTool
            request["tools"] = tools
        }

        // 2. System breakpoint: add to last system part
        if var systemParts = request["system"] as? [[String: Any]], !systemParts.isEmpty {
            var lastPart = systemParts[systemParts.count - 1]
            lastPart["cache_control"] = ephemeral
            systemParts[systemParts.count - 1] = lastPart
            request["system"] = systemParts
        }

        // 3. Messages breakpoint: add to second-to-last user message's last content block
        if var messages = request["messages"] as? [[String: Any]] {
            // Find user message indices
            let userIndices = messages.indices.filter { messages[$0]["role"] as? String == "user" }

            // Need at least 2 user messages
            if userIndices.count >= 2 {
                let targetIndex = userIndices[userIndices.count - 2]
                if var contentArray = messages[targetIndex]["content"] as? [[String: Any]], !contentArray.isEmpty {
                    var lastContent = contentArray[contentArray.count - 1]
                    lastContent["cache_control"] = ephemeral
                    contentArray[contentArray.count - 1] = lastContent
                    messages[targetIndex]["content"] = contentArray
                    request["messages"] = messages
                }
            }
        }
    }

    /// Recursively count `cache_control` keys in a JSON-like structure.
    private static func countCacheControls(_ value: Any) -> Int {
        if let dict = value as? [String: Any] {
            var count = dict.keys.contains("cache_control") ? 1 : 0
            for (_, v) in dict {
                count += countCacheControls(v)
            }
            return count
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + countCacheControls($1) }
        }
        return 0
    }
}

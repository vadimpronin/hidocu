import Foundation
import OSLog

private let logger = Logger(subsystem: "com.llmservice", category: "GeminiModelCatalog")

/// Catalog of Gemini model metadata parsed from Google AI documentation.
///
/// Fetches and caches model information (display names, capabilities, token limits)
/// from the public Google AI models documentation page. Falls back to a hardcoded
/// catalog when the documentation is unavailable.
actor GeminiModelCatalog {

    /// Shared instance for package-wide use.
    static let shared = GeminiModelCatalog()

    private static let documentationURL = URL(
        string: "https://ai.google.dev/gemini-api/docs/models.md.txt"
    )!
    private static let cacheTTL: TimeInterval = 86_400 // 24 hours
    private static let fallbackRetryInterval: TimeInterval = 300 // 5 minutes

    /// Cached catalog entries keyed by model ID.
    private var cache: [String: LLMModelInfo] = [:]
    private var cacheTimestamp: Date?
    private var isFallbackCache = false

    // MARK: - Public API

    /// Returns the full catalog, fetching from documentation if the cache is stale.
    func getCatalog(httpClient: HTTPClient) async -> [String: LLMModelInfo] {
        let ttl = isFallbackCache ? Self.fallbackRetryInterval : Self.cacheTTL
        if let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < ttl,
           !cache.isEmpty {
            return cache
        }

        do {
            let parsed = try await fetchAndParse(httpClient: httpClient)
            cache = parsed
            cacheTimestamp = Date()
            isFallbackCache = false
            logger.info("Refreshed Gemini model catalog: \(parsed.count) models")
            return parsed
        } catch {
            logger.warning("Failed to fetch model catalog, using fallback: \(error.localizedDescription)")
            if !cache.isEmpty && !isFallbackCache {
                return cache
            }
            let fb = Self.fallbackCatalog
            cache = fb
            cacheTimestamp = Date()
            isFallbackCache = true
            return fb
        }
    }

    /// Invalidates the cache, forcing a re-fetch on next access.
    func invalidateCache() {
        cache = [:]
        cacheTimestamp = nil
        isFallbackCache = false
    }

    // MARK: - Fetch & Parse

    private func fetchAndParse(httpClient: HTTPClient) async throws -> [String: LLMModelInfo] {
        var request = URLRequest(url: Self.documentationURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await httpClient.data(for: request)

        guard (200..<300).contains(response.statusCode) else {
            throw LLMServiceError(
                traceId: "catalog",
                message: "Documentation fetch failed with status \(response.statusCode)",
                statusCode: response.statusCode
            )
        }

        guard let markdown = String(data: data, encoding: .utf8) else {
            throw LLMServiceError(traceId: "catalog", message: "Failed to decode documentation as UTF-8")
        }

        return Self.parse(markdown: markdown)
    }

    // MARK: - Markdown Parser

    /// Parses the Google AI models documentation markdown into a dictionary of LLMModelInfo.
    ///
    /// Expected format per model (each model starts with a `### ` heading followed by a table):
    /// ```
    /// ### Gemini 2.5 Pro
    /// | id_cardModel code | `gemini-2.5-pro` |
    /// | saveSupported data types | **Inputs** Text, Image, Video, Audio **Output** Text |
    /// | token_autoToken limits | **Input token limit** 1,048,576 **Output token limit** 65,536 |
    /// | handymanCapabilities | **Function calling** Supported **Thinking** Supported |
    /// ```
    static func parse(markdown: String) -> [String: LLMModelInfo] {
        var results: [String: LLMModelInfo] = [:]
        let lines = markdown.components(separatedBy: "\n")

        var currentDisplayName: String?
        var currentModelCode: String?
        var supportsImage = false
        var supportsAudio = false
        var supportsVideo = false
        var supportsThinking = false
        var supportsTools = false
        var maxInput: Int?
        var maxOutput: Int?

        func flushModel() {
            guard let code = currentModelCode, let name = currentDisplayName else { return }
            results[code] = LLMModelInfo(
                id: code,
                displayName: name,
                supportsText: true,
                supportsImage: supportsImage,
                supportsAudio: supportsAudio,
                supportsVideo: supportsVideo,
                supportsThinking: supportsThinking,
                supportsTools: supportsTools,
                maxInputTokens: maxInput,
                maxOutputTokens: maxOutput
            )
        }

        func resetState() {
            currentDisplayName = nil
            currentModelCode = nil
            supportsImage = false
            supportsAudio = false
            supportsVideo = false
            supportsThinking = false
            supportsTools = false
            maxInput = nil
            maxOutput = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect model heading: ### Model Name (skip "### Expand", "### Model version")
            if trimmed.hasPrefix("### "),
               !trimmed.hasPrefix("### Expand"),
               !trimmed.hasPrefix("### Model version") {
                flushModel()
                resetState()
                currentDisplayName = String(trimmed.dropFirst(4))
                continue
            }

            // Only process table rows
            guard trimmed.hasPrefix("|") else { continue }

            if trimmed.contains("Model code") {
                // Extract model code from backticks: `gemini-xxx`
                if let match = trimmed.range(of: "`[^`]+`", options: .regularExpression) {
                    currentModelCode = String(trimmed[match].dropFirst().dropLast())
                }
            } else if trimmed.contains("Supported data types") {
                let lower = trimmed.lowercased()
                supportsImage = lower.contains("image")
                supportsAudio = lower.contains("audio")
                supportsVideo = lower.contains("video")
            } else if trimmed.contains("Token limits") {
                maxInput = parseTokenLimit(from: trimmed, label: "Input token limit")
                maxOutput = parseTokenLimit(from: trimmed, label: "Output token limit")
            } else if trimmed.contains("Capabilities") {
                let lower = trimmed.lowercased()
                supportsThinking = lower.contains("**thinking** supported")
                supportsTools = lower.contains("**function calling** supported")
            }
        }

        // Flush last model
        flushModel()

        return results
    }

    /// Extracts a token limit number from a table cell like:
    /// `**Input token limit** 1,048,576 **Output token limit** 65,536`
    private static func parseTokenLimit(from text: String, label: String) -> Int? {
        guard let range = text.range(of: "**\(label)**") else { return nil }
        let afterLabel = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)

        var numberStr = ""
        for char in afterLabel {
            if char.isNumber || char == "," {
                numberStr.append(char)
            } else if !numberStr.isEmpty {
                break
            }
        }

        return Int(numberStr.replacingOccurrences(of: ",", with: ""))
    }

    // MARK: - Fallback Catalog

    /// Hardcoded fallback catalog used when the documentation page is unreachable.
    static let fallbackCatalog: [String: LLMModelInfo] = {
        let models: [LLMModelInfo] = [
            LLMModelInfo(
                id: "gemini-3-pro-preview", displayName: "Gemini 3 Pro Preview",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 65_536
            ),
            LLMModelInfo(
                id: "gemini-3-flash-preview", displayName: "Gemini 3 Flash Preview",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 65_536
            ),
            LLMModelInfo(
                id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 65_536
            ),
            LLMModelInfo(
                id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 65_536
            ),
            LLMModelInfo(
                id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash-Lite",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsThinking: true, supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 65_536
            ),
            LLMModelInfo(
                id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash",
                supportsText: true, supportsImage: true, supportsAudio: true, supportsVideo: true,
                supportsTools: true,
                maxInputTokens: 1_048_576, maxOutputTokens: 8_192
            ),
        ]
        var dict: [String: LLMModelInfo] = [:]
        for m in models { dict[m.id] = m }
        return dict
    }()
}

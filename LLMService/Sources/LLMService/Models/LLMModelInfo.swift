public struct LLMModelInfo: Sendable {
    public let id: String
    public let displayName: String
    public let supportsText: Bool
    public let supportsImage: Bool
    public let supportsAudio: Bool
    public let supportsVideo: Bool
    public let supportsThinking: Bool
    public let supportsTools: Bool
    public let supportsStreaming: Bool
    public let supportsNonStreaming: Bool
    public let maxInputTokens: Int?
    public let maxOutputTokens: Int?
    public let contextLength: Int?

    public init(
        id: String,
        displayName: String,
        supportsText: Bool = true,
        supportsImage: Bool = false,
        supportsAudio: Bool = false,
        supportsVideo: Bool = false,
        supportsThinking: Bool = false,
        supportsTools: Bool = false,
        supportsStreaming: Bool = true,
        supportsNonStreaming: Bool = true,
        maxInputTokens: Int? = nil,
        maxOutputTokens: Int? = nil,
        contextLength: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.supportsText = supportsText
        self.supportsImage = supportsImage
        self.supportsAudio = supportsAudio
        self.supportsVideo = supportsVideo
        self.supportsThinking = supportsThinking
        self.supportsTools = supportsTools
        self.supportsStreaming = supportsStreaming
        self.supportsNonStreaming = supportsNonStreaming
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
        self.contextLength = contextLength
    }

    /// Returns a copy with `supportsNonStreaming` set to `false`.
    func withNonStreamingDisabled() -> LLMModelInfo {
        LLMModelInfo(
            id: id, displayName: displayName,
            supportsText: supportsText, supportsImage: supportsImage,
            supportsAudio: supportsAudio, supportsVideo: supportsVideo,
            supportsThinking: supportsThinking, supportsTools: supportsTools,
            supportsStreaming: supportsStreaming, supportsNonStreaming: false,
            maxInputTokens: maxInputTokens, maxOutputTokens: maxOutputTokens,
            contextLength: contextLength
        )
    }

    /// Formats a model ID like "gemini-2.5-pro" into "Gemini 2.5 Pro".
    static func formatDisplayName(from modelId: String) -> String {
        modelId.split(separator: "-")
            .map { segment in
                let s = String(segment)
                if s.first?.isNumber == true { return s }
                return s.prefix(1).uppercased() + s.dropFirst()
            }
            .joined(separator: " ")
    }
}

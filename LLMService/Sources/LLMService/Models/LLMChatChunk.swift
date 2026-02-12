public struct LLMChatChunk: Sendable {
    public let id: String
    public let partType: LLMPartTypeDelta
    public let delta: String
    public let usage: LLMUsage?

    public init(
        id: String,
        partType: LLMPartTypeDelta,
        delta: String,
        usage: LLMUsage? = nil
    ) {
        self.id = id
        self.partType = partType
        self.delta = delta
        self.usage = usage
    }
}

public enum LLMPartTypeDelta: Sendable {
    case thinking
    case text
    case toolCall(id: String, function: String)
}

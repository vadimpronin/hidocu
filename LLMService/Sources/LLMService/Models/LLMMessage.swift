public struct LLMMessage: Sendable {
    public let role: LLMChatRole
    public let content: [LLMContent]

    public init(role: LLMChatRole, content: [LLMContent]) {
        self.role = role
        self.content = content
    }

    public enum LLMChatRole: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }
}

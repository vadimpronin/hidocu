import Foundation

public struct LLMResponse: Sendable {
    public let id: String
    public let model: String
    public let traceId: String
    public let content: [LLMResponsePart]
    public let usage: LLMUsage?

    public var fullText: String {
        content.compactMap {
            if case .text(let str) = $0 { return str }
            return nil
        }.joined()
    }

    public init(
        id: String,
        model: String,
        traceId: String,
        content: [LLMResponsePart],
        usage: LLMUsage?
    ) {
        self.id = id
        self.model = model
        self.traceId = traceId
        self.content = content
        self.usage = usage
    }
}

public enum LLMResponsePart: Sendable {
    case thinking(String)
    case text(String)
    case toolCall(id: String, function: String, arguments: String)
    case inlineData(Data, mimeType: String)
}

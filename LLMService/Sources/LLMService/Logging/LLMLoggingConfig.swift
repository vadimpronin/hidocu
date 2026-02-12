import Foundation

public struct LLMLoggingConfig: Sendable {
    public let subsystem: String
    public let storageDirectory: URL?
    public let shouldMaskTokens: Bool
    public let onTraceSent: (@Sendable (LLMTraceEntry) -> Void)?
    public let onTraceRecorded: (@Sendable (LLMTraceEntry) -> Void)?

    public init(
        subsystem: String = "com.llmservice",
        storageDirectory: URL? = nil,
        shouldMaskTokens: Bool = true,
        onTraceSent: (@Sendable (LLMTraceEntry) -> Void)? = nil,
        onTraceRecorded: (@Sendable (LLMTraceEntry) -> Void)? = nil
    ) {
        self.subsystem = subsystem
        self.storageDirectory = storageDirectory
        self.shouldMaskTokens = shouldMaskTokens
        self.onTraceSent = onTraceSent
        self.onTraceRecorded = onTraceRecorded
    }
}

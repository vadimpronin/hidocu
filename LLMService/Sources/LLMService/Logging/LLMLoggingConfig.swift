import Foundation

public struct LLMLoggingConfig: Sendable {
    public let subsystem: String
    public let storageDirectory: URL?
    public let shouldMaskTokens: Bool

    public init(
        subsystem: String = "com.llmservice",
        storageDirectory: URL? = nil,
        shouldMaskTokens: Bool = true
    ) {
        self.subsystem = subsystem
        self.storageDirectory = storageDirectory
        self.shouldMaskTokens = shouldMaskTokens
    }
}

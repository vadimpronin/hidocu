public struct LLMAccountInfo: Codable, Sendable {
    public let appUniqueKey: String?
    public let provider: LLMProvider
    public var identifier: String?
    public var displayName: String?
    public var metadata: [String: String]

    public init(
        provider: LLMProvider,
        appUniqueKey: String? = nil,
        identifier: String? = nil,
        displayName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.provider = provider
        self.appUniqueKey = appUniqueKey
        self.identifier = identifier
        self.displayName = displayName
        self.metadata = metadata
    }
}

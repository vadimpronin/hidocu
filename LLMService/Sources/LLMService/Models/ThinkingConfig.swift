public struct ThinkingConfig: Sendable {
    public enum ThinkingType: Sendable {
        case enabled(budgetTokens: Int)
        case disabled
        case adaptive
    }

    public let type: ThinkingType

    public init(type: ThinkingType) {
        self.type = type
    }

    public static func enabled(budgetTokens: Int) -> ThinkingConfig {
        ThinkingConfig(type: .enabled(budgetTokens: budgetTokens))
    }

    public static let disabled = ThinkingConfig(type: .disabled)
    public static let adaptive = ThinkingConfig(type: .adaptive)
}

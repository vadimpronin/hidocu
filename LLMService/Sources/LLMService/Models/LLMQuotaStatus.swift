import Foundation

public struct LLMQuotaStatus: Sendable {
    public let modelId: String
    public let isAvailable: Bool
    public let resetIn: TimeInterval?
    public let remainingRequests: Int?

    public init(
        modelId: String,
        isAvailable: Bool,
        resetIn: TimeInterval? = nil,
        remainingRequests: Int? = nil
    ) {
        self.modelId = modelId
        self.isAvailable = isAvailable
        self.resetIn = resetIn
        self.remainingRequests = remainingRequests
    }
}

import Foundation

public struct LLMServiceError: LocalizedError, Sendable {
    public let traceId: String
    public let message: String
    public let statusCode: Int?
    public let underlyingErrorDescription: String?

    public init(
        traceId: String,
        message: String,
        statusCode: Int? = nil,
        underlyingError: (any Error)? = nil
    ) {
        self.traceId = traceId
        self.message = message
        self.statusCode = statusCode
        self.underlyingErrorDescription = underlyingError?.localizedDescription
    }

    public var errorDescription: String? {
        if let statusCode {
            return "[\(statusCode)] \(message)"
        }
        return message
    }
}

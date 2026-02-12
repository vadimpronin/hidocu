import Foundation

public struct LLMCredentials: Sendable {
    public var apiKey: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(
        apiKey: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

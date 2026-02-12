import Foundation

public struct LLMTraceEntry: Codable, Sendable, Identifiable {
    /// Uses `requestId` as identity so the "sent" and "recorded" phases of the same request
    /// resolve to the same entry in the UI.
    public var id: String { requestId }
    public let traceId: String
    public let requestId: String
    public let timestamp: Date
    public let provider: String
    public let accountIdentifier: String?
    public let method: String
    public let isStreaming: Bool
    public var request: HTTPDetails
    public var response: HTTPDetails?
    public var error: String?
    public var duration: TimeInterval?

    public init(
        traceId: String,
        requestId: String,
        timestamp: Date = Date(),
        provider: String,
        accountIdentifier: String? = nil,
        method: String,
        isStreaming: Bool,
        request: HTTPDetails,
        response: HTTPDetails? = nil,
        error: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.traceId = traceId
        self.requestId = requestId
        self.timestamp = timestamp
        self.provider = provider
        self.accountIdentifier = accountIdentifier
        self.method = method
        self.isStreaming = isStreaming
        self.request = request
        self.response = response
        self.error = error
        self.duration = duration
    }

    public struct HTTPDetails: Codable, Sendable {
        public let url: String?
        public let method: String?
        public let headers: [String: String]?
        public let body: String?
        public let statusCode: Int?

        public init(
            url: String? = nil,
            method: String? = nil,
            headers: [String: String]? = nil,
            body: String? = nil,
            statusCode: Int? = nil
        ) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
            self.statusCode = statusCode
        }

        public init(from request: URLRequest) {
            self.init(
                url: request.url?.absoluteString,
                method: request.httpMethod,
                headers: request.allHTTPHeaderFields,
                body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            )
        }

        public init(from response: HTTPURLResponse, body: String? = nil) {
            var headerDict: [String: String] = [:]
            for (key, value) in response.allHeaderFields {
                headerDict["\(key)"] = "\(value)"
            }
            self.init(
                headers: headerDict.isEmpty ? nil : headerDict,
                body: body,
                statusCode: response.statusCode
            )
        }
    }
}

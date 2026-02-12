import Foundation

/// Production HTTPClient using URLSession with proxy support
public final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(proxyURL: URL? = nil) {
        let config = URLSessionConfiguration.default
        if let proxyURL = proxyURL {
            var proxyDict: [AnyHashable: Any] = [:]
            if proxyURL.scheme == "http" || proxyURL.scheme == "https" {
                proxyDict[kCFNetworkProxiesHTTPEnable] = true
                proxyDict[kCFNetworkProxiesHTTPProxy] = proxyURL.host
                proxyDict[kCFNetworkProxiesHTTPPort] = proxyURL.port
            }
            config.connectionProxyDictionary = proxyDict
        }
        self.session = URLSession(configuration: config)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }

    public func bytes(for request: URLRequest) async throws -> (AnyAsyncSequence<UInt8>, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (AnyAsyncSequence(bytes), httpResponse)
    }
}

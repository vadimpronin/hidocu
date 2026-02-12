import Foundation
@testable import LLMService

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    struct Response {
        let data: Data
        let statusCode: Int
        let headers: [String: String]

        static func json(_ object: Any, statusCode: Int = 200) -> Response {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return Response(data: data, statusCode: statusCode, headers: ["Content-Type": "application/json"])
        }

        static func error(_ statusCode: Int, message: String = "") -> Response {
            Response(data: Data(message.utf8), statusCode: statusCode, headers: [:])
        }

        static func sse(_ events: String) -> Response {
            Response(data: Data(events.utf8), statusCode: 200, headers: ["Content-Type": "text/event-stream"])
        }
    }

    private enum QueuedItem {
        case response(Response)
        case error(Error)
    }

    private var responseQueue: [QueuedItem] = []
    private(set) var capturedRequests: [URLRequest] = []

    var requestCount: Int { capturedRequests.count }

    func enqueue(_ response: Response) {
        responseQueue.append(.response(response))
    }

    func enqueueMultiple(_ responses: [Response]) {
        for response in responses {
            responseQueue.append(.response(response))
        }
    }

    func enqueueError(_ error: Error) {
        responseQueue.append(.error(error))
    }

    private func nextItem() -> QueuedItem {
        guard !responseQueue.isEmpty else {
            return .response(.error(500, message: "No mock response enqueued"))
        }
        return responseQueue.removeFirst()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequests.append(request)
        let item = nextItem()
        switch item {
        case .error(let error):
            throw error
        case .response(let response):
            let httpResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mock.test")!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            return (response.data, httpResponse)
        }
    }

    func bytes(for request: URLRequest) async throws -> (AnyAsyncSequence<UInt8>, HTTPURLResponse) {
        capturedRequests.append(request)
        let item = nextItem()
        switch item {
        case .error(let error):
            throw error
        case .response(let response):
            let httpResponse = HTTPURLResponse(
                url: request.url ?? URL(string: "https://mock.test")!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )!
            let asyncBytes = AsyncStream<UInt8> { continuation in
                for byte in response.data {
                    continuation.yield(byte)
                }
                continuation.finish()
            }
            return (AnyAsyncSequence(asyncBytes), httpResponse)
        }
    }
}

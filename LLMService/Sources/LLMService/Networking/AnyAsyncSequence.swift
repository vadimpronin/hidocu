public struct AnyAsyncSequence<Element>: AsyncSequence, Sendable {
    public typealias AsyncIterator = AnyAsyncIterator<Element>

    private let makeIteratorClosure: @Sendable () -> AnyAsyncIterator<Element>

    public init<S: AsyncSequence & Sendable>(
        _ sequence: S
    ) where S.Element == Element {
        makeIteratorClosure = {
            var iterator = sequence.makeAsyncIterator()
            return AnyAsyncIterator {
                try await iterator.next()
            }
        }
    }

    public func makeAsyncIterator() -> AnyAsyncIterator<Element> {
        makeIteratorClosure()
    }
}

public struct AnyAsyncIterator<Element>: AsyncIteratorProtocol {
    private let nextClosure: () async throws -> Element?

    public init(_ nextClosure: @escaping () async throws -> Element?) {
        self.nextClosure = nextClosure
    }

    public mutating func next() async throws -> Element? {
        try await nextClosure()
    }
}

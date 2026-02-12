import XCTest
@testable import LLMService

final class GoogleCloudStreamParserTests: XCTestCase {
    func testParseTextDelta() {
        let parser = GoogleCloudStreamParser()
        let sseData = """
        data: {"response":{"responseId":"resp-1","modelVersion":"gemini-pro","candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks.first?.delta, "Hello")
        if case .text = chunks.first?.partType {} else {
            XCTFail("Expected text part type")
        }
    }

    func testParseThinkingDelta() {
        let parser = GoogleCloudStreamParser()
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"text":"I'm thinking...","thought":true}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertFalse(chunks.isEmpty)
        if case .thinking = chunks.first?.partType {} else {
            XCTFail("Expected thinking part type")
        }
    }

    func testParseDone() {
        let parser = GoogleCloudStreamParser()
        // First send some content
        _ = parser.parseSSELine("data: {\"response\":{\"responseId\":\"r1\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"}]}}]}}")
        let doneChunks = parser.parseSSELine("data: [DONE]")
        // Should finalize
        XCTAssertNotNil(doneChunks)
    }

    func testUsageInFinalChunk() {
        let parser = GoogleCloudStreamParser()
        let sseData = """
        data: {"response":{"responseId":"r1","candidates":[{"content":{"parts":[{"text":"done"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5,"totalTokenCount":15}}}
        """

        let chunks = parser.parseSSELine(sseData)
        let usageChunk = chunks.last(where: { $0.usage != nil })
        XCTAssertNotNil(usageChunk?.usage)
        XCTAssertEqual(usageChunk?.usage?.inputTokens, 10)
        XCTAssertEqual(usageChunk?.usage?.outputTokens, 5)
    }
}

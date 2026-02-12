import XCTest
@testable import LLMService

final class GeminiStreamParserTests: XCTestCase {
    func testParseTextDelta() {
        let parser = GeminiStreamParser()
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
        let parser = GeminiStreamParser()
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
        let parser = GeminiStreamParser()
        // First send some content
        _ = parser.parseSSELine("data: {\"response\":{\"responseId\":\"r1\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"}]}}]}}")
        let doneChunks = parser.parseSSELine("data: [DONE]")
        // Should finalize
        XCTAssertNotNil(doneChunks)
    }

    func testUsageInFinalChunk() {
        let parser = GeminiStreamParser()
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

// MARK: - Gemini InlineData Tests

extension GeminiStreamParserTests {
    func testParseInlineDataCamelCase() {
        let parser = GeminiStreamParser()
        let base64 = "iVBORw0KGgo="
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"\(base64)"}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertEqual(chunks.count, 1)
        if case .inlineData(let mimeType) = chunks.first?.partType {
            XCTAssertEqual(mimeType, "image/png")
        } else {
            XCTFail("Expected inlineData part type")
        }
        XCTAssertEqual(chunks.first?.delta, base64)
    }

    func testParseInlineDataSnakeCase() {
        let parser = GeminiStreamParser()
        let base64 = "iVBORw0KGgo="
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inline_data":{"mime_type":"image/jpeg","data":"\(base64)"}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertEqual(chunks.count, 1)
        if case .inlineData(let mimeType) = chunks.first?.partType {
            XCTAssertEqual(mimeType, "image/jpeg")
        } else {
            XCTFail("Expected inlineData part type")
        }
    }

    func testParseInlineDataMissingMimeType() {
        let parser = GeminiStreamParser()
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"data":"iVBORw0KGgo="}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertEqual(chunks.count, 1)
        if case .inlineData(let mimeType) = chunks.first?.partType {
            XCTAssertEqual(mimeType, "image/png", "Should default to image/png")
        } else {
            XCTFail("Expected inlineData part type")
        }
    }

    func testParseInlineDataEmptyDataSkipped() {
        let parser = GeminiStreamParser()
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":""}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertTrue(chunks.isEmpty, "Empty inlineData should be skipped")
    }

    func testParseInlineDataMixedWithText() {
        let parser = GeminiStreamParser()

        // First: text chunk
        let textSSE = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"text":"Here is an image:"}]}}]}}
        """
        let textChunks = parser.parseSSELine(textSSE)
        XCTAssertEqual(textChunks.count, 1)
        if case .text = textChunks.first?.partType {} else {
            XCTFail("Expected text part type")
        }

        // Second: inlineData chunk
        let imageSSE = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"iVBORw0KGgo="}}]}}]}}
        """
        let imageChunks = parser.parseSSELine(imageSSE)
        XCTAssertEqual(imageChunks.count, 1)
        if case .inlineData(let mimeType) = imageChunks.first?.partType {
            XCTAssertEqual(mimeType, "image/png")
        } else {
            XCTFail("Expected inlineData part type")
        }

        // Third: more text
        let textSSE2 = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"text":" Pretty cool!"}]}}]}}
        """
        let textChunks2 = parser.parseSSELine(textSSE2)
        XCTAssertEqual(textChunks2.count, 1)
        if case .text = textChunks2.first?.partType {} else {
            XCTFail("Expected text part type after inlineData")
        }
    }
}

// MARK: - Antigravity Tests

final class AntigravityStreamParserTests: XCTestCase {
    func testParseTextDelta() {
        let parser = AntigravityStreamParser()
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
        let parser = AntigravityStreamParser()
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
        let parser = AntigravityStreamParser()
        _ = parser.parseSSELine("data: {\"response\":{\"responseId\":\"r1\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"}]}}]}}")
        let doneChunks = parser.parseSSELine("data: [DONE]")
        XCTAssertNotNil(doneChunks)
    }

    func testUsageInFinalChunk() {
        let parser = AntigravityStreamParser()
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

// MARK: - Antigravity InlineData Tests

extension AntigravityStreamParserTests {
    func testParseInlineDataCamelCase() {
        let parser = AntigravityStreamParser()
        let base64 = "iVBORw0KGgo="
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"\(base64)"}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertEqual(chunks.count, 1)
        if case .inlineData(let mimeType) = chunks.first?.partType {
            XCTAssertEqual(mimeType, "image/png")
        } else {
            XCTFail("Expected inlineData part type")
        }
        XCTAssertEqual(chunks.first?.delta, base64)
    }

    func testParseInlineDataSnakeCase() {
        let parser = AntigravityStreamParser()
        let base64 = "iVBORw0KGgo="
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inline_data":{"mime_type":"image/jpeg","data":"\(base64)"}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertEqual(chunks.count, 1)
        if case .inlineData(let mimeType) = chunks.first?.partType {
            XCTAssertEqual(mimeType, "image/jpeg")
        } else {
            XCTFail("Expected inlineData part type")
        }
    }

    func testParseInlineDataMissingMimeType() {
        let parser = AntigravityStreamParser()
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"data":"iVBORw0KGgo="}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertEqual(chunks.count, 1)
        if case .inlineData(let mimeType) = chunks.first?.partType {
            XCTAssertEqual(mimeType, "image/png", "Should default to image/png")
        } else {
            XCTFail("Expected inlineData part type")
        }
    }

    func testParseInlineDataEmptyDataSkipped() {
        let parser = AntigravityStreamParser()
        let sseData = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":""}}]}}]}}
        """

        let chunks = parser.parseSSELine(sseData)
        XCTAssertTrue(chunks.isEmpty, "Empty inlineData should be skipped")
    }

    func testParseInlineDataMixedWithText() {
        let parser = AntigravityStreamParser()

        // First: text chunk
        let textSSE = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"text":"Here is an image:"}]}}]}}
        """
        let textChunks = parser.parseSSELine(textSSE)
        XCTAssertEqual(textChunks.count, 1)
        if case .text = textChunks.first?.partType {} else {
            XCTFail("Expected text part type")
        }

        // Second: inlineData chunk
        let imageSSE = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"iVBORw0KGgo="}}]}}]}}
        """
        let imageChunks = parser.parseSSELine(imageSSE)
        XCTAssertEqual(imageChunks.count, 1)
        if case .inlineData(let mimeType) = imageChunks.first?.partType {
            XCTAssertEqual(mimeType, "image/png")
        } else {
            XCTFail("Expected inlineData part type")
        }

        // Third: more text
        let textSSE2 = """
        data: {"response":{"responseId":"resp-1","candidates":[{"content":{"parts":[{"text":" Pretty cool!"}]}}]}}
        """
        let textChunks2 = parser.parseSSELine(textSSE2)
        XCTAssertEqual(textChunks2.count, 1)
        if case .text = textChunks2.first?.partType {} else {
            XCTFail("Expected text part type after inlineData")
        }
    }
}

import XCTest
@testable import LLMService

final class ClaudeStreamParserTests: XCTestCase {
    func testParseMessageStart() {
        let parser = ClaudeStreamParser()
        let data = try! JSONSerialization.data(withJSONObject: [
            "type": "message_start",
            "message": ["id": "msg-1", "model": "claude-3", "role": "assistant", "content": [], "usage": ["input_tokens": 10, "output_tokens": 0]]
        ])
        let chunks = parser.parseSSEEvent(eventType: "message_start", data: data)
        XCTAssertTrue(chunks.isEmpty) // message_start doesn't emit chunks
    }

    func testParseTextDelta() {
        let parser = ClaudeStreamParser()

        // Start a text block
        let startData = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_start",
            "index": 0,
            "content_block": ["type": "text", "text": ""]
        ] as [String: Any])
        _ = parser.parseSSEEvent(eventType: "content_block_start", data: startData)

        // Delta
        let deltaData = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_delta",
            "index": 0,
            "delta": ["type": "text_delta", "text": "Hello world"]
        ] as [String: Any])
        let chunks = parser.parseSSEEvent(eventType: "content_block_delta", data: deltaData)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].delta, "Hello world")
        if case .text = chunks[0].partType {} else { XCTFail("Expected text") }
    }

    func testParseThinkingDelta() {
        let parser = ClaudeStreamParser()

        let startData = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_start",
            "index": 0,
            "content_block": ["type": "thinking", "thinking": ""]
        ] as [String: Any])
        _ = parser.parseSSEEvent(eventType: "content_block_start", data: startData)

        let deltaData = try! JSONSerialization.data(withJSONObject: [
            "type": "content_block_delta",
            "index": 0,
            "delta": ["type": "thinking_delta", "thinking": "Let me think..."]
        ] as [String: Any])
        let chunks = parser.parseSSEEvent(eventType: "content_block_delta", data: deltaData)

        XCTAssertEqual(chunks.count, 1)
        if case .thinking = chunks[0].partType {} else { XCTFail("Expected thinking") }
    }

    func testParseSSEText() {
        let parser = ClaudeStreamParser()
        let sse = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg-1","model":"claude-3","role":"assistant","content":[],"usage":{"input_tokens":5,"output_tokens":0}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi!"}}
        """

        let chunks = parser.parseSSEText(sse)
        let textChunks = chunks.filter { if case .text = $0.partType { return true }; return false }
        XCTAssertFalse(textChunks.isEmpty)
        XCTAssertEqual(textChunks.first?.delta, "Hi!")
    }
}

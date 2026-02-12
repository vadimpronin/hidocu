import XCTest
@testable import LLMService

final class ClaudeRequestBuilderTests: XCTestCase {
    func testSimpleMessage() {
        let messages = [LLMMessage(role: .user, content: [.text("hello")])]
        let result = ClaudeRequestBuilder.buildRequest(modelId: "claude-3", messages: messages, thinking: nil, stream: false)

        XCTAssertEqual(result["model"] as? String, "claude-3")
        XCTAssertEqual(result["stream"] as? Bool, false)

        let msgs = result["messages"] as? [[String: Any]]
        XCTAssertEqual(msgs?.count, 1)
        XCTAssertEqual(msgs?[0]["role"] as? String, "user")
    }

    func testSystemMessage() {
        let messages = [
            LLMMessage(role: .system, content: [.text("Be helpful")]),
            LLMMessage(role: .user, content: [.text("hi")])
        ]
        let result = ClaudeRequestBuilder.buildRequest(modelId: "claude-3", messages: messages, thinking: nil, stream: false)

        let system = result["system"] as? [[String: Any]]
        XCTAssertNotNil(system)
        XCTAssertEqual(system?[0]["text"] as? String, "Be helpful")
    }

    func testThinkingEnabled() {
        let messages = [LLMMessage(role: .user, content: [.text("think")])]
        let result = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3",
            messages: messages,
            thinking: .enabled(budgetTokens: 2048),
            stream: true
        )

        let thinking = result["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 2048)
    }

    func testStreamFlag() {
        let messages = [LLMMessage(role: .user, content: [.text("test")])]
        let streamResult = ClaudeRequestBuilder.buildRequest(modelId: "claude-3", messages: messages, thinking: nil, stream: true)
        let nonStreamResult = ClaudeRequestBuilder.buildRequest(modelId: "claude-3", messages: messages, thinking: nil, stream: false)

        XCTAssertEqual(streamResult["stream"] as? Bool, true)
        XCTAssertEqual(nonStreamResult["stream"] as? Bool, false)
    }

    func testThinkingContentBlock() {
        let messages = [
            LLMMessage(role: .assistant, content: [
                .thinking("Let me think...", signature: "sig123abc"),
                .text("Here is my answer"),
            ])
        ]
        let result = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3", messages: messages, thinking: nil, stream: false
        )

        let msgs = result["messages"] as? [[String: Any]]
        let content = msgs?[0]["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2)

        // Thinking block
        XCTAssertEqual(content?[0]["type"] as? String, "thinking")
        XCTAssertEqual(content?[0]["thinking"] as? String, "Let me think...")
        XCTAssertEqual(content?[0]["signature"] as? String, "sig123abc")

        // Text block
        XCTAssertEqual(content?[1]["type"] as? String, "text")
        XCTAssertEqual(content?[1]["text"] as? String, "Here is my answer")
    }

    func testThinkingContentWithoutSignature() {
        let messages = [
            LLMMessage(role: .assistant, content: [
                .thinking("thinking text", signature: nil),
            ])
        ]
        let result = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3", messages: messages, thinking: nil, stream: false
        )

        let msgs = result["messages"] as? [[String: Any]]
        let content = msgs?[0]["content"] as? [[String: Any]]
        XCTAssertEqual(content?[0]["type"] as? String, "thinking")
        XCTAssertNil(content?[0]["signature"])
    }
}

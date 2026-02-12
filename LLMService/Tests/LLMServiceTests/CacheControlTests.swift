import XCTest
@testable import LLMService

final class CacheControlTests: XCTestCase {

    // MARK: - Tools Breakpoint

    func testCacheControlInjectedOnLastTool() {
        let messages = [LLMMessage(role: .user, content: [.text("hello")])]
        let request = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3",
            messages: messages,
            thinking: nil,
            stream: true,
            tools: [
                ["name": "tool1", "description": "first"],
                ["name": "tool2", "description": "second"],
            ]
        )

        let tools = request["tools"] as? [[String: Any]]
        XCTAssertNotNil(tools)
        XCTAssertEqual(tools?.count, 2)

        // First tool should NOT have cache_control
        let firstTool = tools?[0]
        XCTAssertNil(firstTool?["cache_control"])

        // Last tool should have cache_control
        let lastTool = tools?[1]
        let cc = lastTool?["cache_control"] as? [String: String]
        XCTAssertEqual(cc?["type"], "ephemeral")
    }

    // MARK: - System Breakpoint

    func testCacheControlInjectedOnLastSystem() {
        let messages = [
            LLMMessage(role: .system, content: [.text("Be helpful"), .text("Be safe")]),
            LLMMessage(role: .user, content: [.text("hello")]),
        ]
        let request = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3",
            messages: messages,
            thinking: nil,
            stream: true
        )

        let systemParts = request["system"] as? [[String: Any]]
        XCTAssertNotNil(systemParts)
        XCTAssertEqual(systemParts?.count, 2)

        // First system part should NOT have cache_control
        XCTAssertNil(systemParts?[0]["cache_control"])

        // Last system part should have cache_control
        let cc = systemParts?[1]["cache_control"] as? [String: String]
        XCTAssertEqual(cc?["type"], "ephemeral")
    }

    // MARK: - Messages Breakpoint

    func testCacheControlInjectedOnSecondToLastUserMessage() {
        let messages = [
            LLMMessage(role: .user, content: [.text("first user msg")]),
            LLMMessage(role: .assistant, content: [.text("response")]),
            LLMMessage(role: .user, content: [.text("second user msg")]),
            LLMMessage(role: .assistant, content: [.text("response 2")]),
            LLMMessage(role: .user, content: [.text("third user msg")]),
        ]
        let request = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3",
            messages: messages,
            thinking: nil,
            stream: true
        )

        let msgs = request["messages"] as? [[String: Any]]
        XCTAssertNotNil(msgs)
        XCTAssertEqual(msgs?.count, 5)

        // Second-to-last user message (index 2 = "second user msg") should have cache_control
        // on its last content block.
        let targetMsg = msgs?[2]
        XCTAssertEqual(targetMsg?["role"] as? String, "user")
        let contentArray = targetMsg?["content"] as? [[String: Any]]
        let lastContent = contentArray?.last
        let cc = lastContent?["cache_control"] as? [String: String]
        XCTAssertEqual(cc?["type"], "ephemeral")

        // Last user message should NOT have cache_control
        let lastUserMsg = msgs?[4]
        let lastUserContent = lastUserMsg?["content"] as? [[String: Any]]
        XCTAssertNil(lastUserContent?.last?["cache_control"])
    }

    // MARK: - Skip When Already Present

    func testCacheControlSkippedWhenAlreadyPresent() {
        // Manually construct a request dict with cache_control already present
        var request: [String: Any] = [
            "model": "claude-3",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "hello", "cache_control": ["type": "ephemeral"]]
                    ]
                ] as [String: Any],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "world"]
                    ]
                ] as [String: Any],
            ] as [[String: Any]],
            "tools": [
                ["name": "tool1", "description": "test"]
            ] as [[String: Any]],
        ]

        ClaudeRequestBuilder.ensureCacheControl(&request)

        // Tools should NOT get cache_control since one was already present
        let tools = request["tools"] as? [[String: Any]]
        XCTAssertNil(tools?[0]["cache_control"])
    }

    // MARK: - Skip With Insufficient User Messages

    func testCacheControlSkippedWithLessThanTwoUserMessages() {
        let messages = [
            LLMMessage(role: .user, content: [.text("only one user msg")]),
        ]
        let request = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3",
            messages: messages,
            thinking: nil,
            stream: true
        )

        // Single user message → messages breakpoint should not apply
        let msgs = request["messages"] as? [[String: Any]]
        let content = msgs?[0]["content"] as? [[String: Any]]
        XCTAssertNil(content?.last?["cache_control"])
    }

    // MARK: - All Three Breakpoints Together

    func testAllThreeBreakpoints() {
        let messages = [
            LLMMessage(role: .system, content: [.text("system prompt")]),
            LLMMessage(role: .user, content: [.text("user 1")]),
            LLMMessage(role: .assistant, content: [.text("reply")]),
            LLMMessage(role: .user, content: [.text("user 2")]),
        ]
        let request = ClaudeRequestBuilder.buildRequest(
            modelId: "claude-3",
            messages: messages,
            thinking: nil,
            stream: true,
            tools: [["name": "search", "description": "search tool"]]
        )

        // Tool breakpoint
        let tools = request["tools"] as? [[String: Any]]
        XCTAssertNotNil(tools?.last?["cache_control"])

        // System breakpoint
        let system = request["system"] as? [[String: Any]]
        XCTAssertNotNil(system?.last?["cache_control"])

        // Messages breakpoint on first user message (second-to-last user)
        let msgs = request["messages"] as? [[String: Any]]
        let firstUserContent = msgs?[0]["content"] as? [[String: Any]]
        let cc = firstUserContent?.last?["cache_control"] as? [String: String]
        XCTAssertEqual(cc?["type"], "ephemeral")
    }
}

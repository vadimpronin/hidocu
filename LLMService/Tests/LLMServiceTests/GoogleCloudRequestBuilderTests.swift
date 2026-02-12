import XCTest
@testable import LLMService

final class GeminiRequestBuilderTests: XCTestCase {
    func testSimpleUserMessage() {
        let messages = [LLMMessage(role: .user, content: [.text("hello")])]
        let result = GeminiRequestBuilder.buildRequest(modelName: "gemini-pro", messages: messages, thinking: nil)

        // Check structure
        XCTAssertEqual(result["model"] as? String, "gemini-pro")
        let request = result["request"] as? [String: Any]
        XCTAssertNotNil(request)

        let contents = request?["contents"] as? [[String: Any]]
        XCTAssertNotNil(contents)
        XCTAssertEqual(contents?.count, 1)
        XCTAssertEqual(contents?[0]["role"] as? String, "user")

        let parts = contents?[0]["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?[0]["text"] as? String, "hello")
    }

    func testSystemMessageExtraction() {
        let messages = [
            LLMMessage(role: .system, content: [.text("You are helpful")]),
            LLMMessage(role: .user, content: [.text("hi")])
        ]
        let result = GeminiRequestBuilder.buildRequest(modelName: "gemini-pro", messages: messages, thinking: nil)
        let request = result["request"] as? [String: Any]

        let sysInstruction = request?["systemInstruction"] as? [String: Any]
        XCTAssertNotNil(sysInstruction)
        XCTAssertEqual(sysInstruction?["role"] as? String, "user")

        let sysParts = sysInstruction?["parts"] as? [[String: Any]]
        XCTAssertEqual(sysParts?[0]["text"] as? String, "You are helpful")
    }

    func testAssistantRoleMappedToModel() {
        let messages = [
            LLMMessage(role: .user, content: [.text("hi")]),
            LLMMessage(role: .assistant, content: [.text("hello")])
        ]
        let result = GeminiRequestBuilder.buildRequest(modelName: "gemini-pro", messages: messages, thinking: nil)
        let request = result["request"] as? [String: Any]
        let contents = request?["contents"] as? [[String: Any]]
        XCTAssertEqual(contents?[1]["role"] as? String, "model")
    }

    func testThinkingConfigEnabled() {
        let messages = [LLMMessage(role: .user, content: [.text("think")])]
        let result = GeminiRequestBuilder.buildRequest(
            modelName: "gemini-pro",
            messages: messages,
            thinking: .enabled(budgetTokens: 1024)
        )
        let request = result["request"] as? [String: Any]
        let genConfig = request?["generationConfig"] as? [String: Any]
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertEqual(thinkingConfig?["thinkingBudget"] as? Int, 1024)
        XCTAssertEqual(thinkingConfig?["includeThoughts"] as? Bool, true)
    }

    func testSafetySettingsAttached() {
        let messages = [LLMMessage(role: .user, content: [.text("test")])]
        let result = GeminiRequestBuilder.buildRequest(modelName: "gemini-pro", messages: messages, thinking: nil)
        let request = result["request"] as? [String: Any]
        let safety = request?["safetySettings"] as? [[String: String]]
        XCTAssertEqual(safety?.count, 5)
    }

    func testThinkingContentWithSignature() {
        let messages = [
            LLMMessage(role: .user, content: [.text("hi")]),
            LLMMessage(role: .assistant, content: [
                .thinking("Let me analyze...", signature: "cached_sig_value"),
                .text("Here is my answer"),
            ]),
            LLMMessage(role: .user, content: [.text("follow up")]),
        ]
        let result = GeminiRequestBuilder.buildRequest(
            modelName: "gemini-2.5-pro", messages: messages, thinking: nil
        )
        let request = result["request"] as? [String: Any]
        let contents = request?["contents"] as? [[String: Any]]
        XCTAssertEqual(contents?.count, 3)

        // Assistant (model) message with thinking + text
        let assistantMsg = contents?[1]
        XCTAssertEqual(assistantMsg?["role"] as? String, "model")
        let parts = assistantMsg?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.count, 2)

        // Thinking part
        let thinkingPart = parts?[0]
        XCTAssertEqual(thinkingPart?["text"] as? String, "Let me analyze...")
        XCTAssertEqual(thinkingPart?["thought"] as? Bool, true)
        XCTAssertEqual(thinkingPart?["thoughtSignature"] as? String, "cached_sig_value")

        // Text part
        let textPart = parts?[1]
        XCTAssertEqual(textPart?["text"] as? String, "Here is my answer")
        XCTAssertNil(textPart?["thought"])
    }

    func testThinkingContentWithoutSignature() {
        let messages = [
            LLMMessage(role: .assistant, content: [
                .thinking("thinking...", signature: nil),
            ]),
        ]
        let result = GeminiRequestBuilder.buildRequest(
            modelName: "gemini-2.5-pro", messages: messages, thinking: nil
        )
        let request = result["request"] as? [String: Any]
        let contents = request?["contents"] as? [[String: Any]]
        let parts = contents?[0]["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?[0]["thought"] as? Bool, true)
        XCTAssertNil(parts?[0]["thoughtSignature"])
    }
}

final class AntigravityRequestBuilderTests: XCTestCase {
    func testSimpleUserMessage() {
        let messages = [LLMMessage(role: .user, content: [.text("hello")])]
        let result = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-pro", messages: messages, thinking: nil, projectId: "test-proj"
        )

        // Check envelope
        XCTAssertEqual(result["model"] as? String, "gemini-pro")
        XCTAssertEqual(result["userAgent"] as? String, "antigravity")
        XCTAssertEqual(result["requestType"] as? String, "agent")
        XCTAssertEqual(result["project"] as? String, "test-proj")
        XCTAssertNotNil(result["requestId"])

        // Check inner request
        let request = result["request"] as? [String: Any]
        XCTAssertNotNil(request)
        let contents = request?["contents"] as? [[String: Any]]
        XCTAssertNotNil(contents)
    }

    func testNoSafetySettings() {
        let messages = [LLMMessage(role: .user, content: [.text("test")])]
        let result = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-pro", messages: messages, thinking: nil, projectId: "proj"
        )
        let request = result["request"] as? [String: Any]
        XCTAssertNil(request?["safetySettings"], "Antigravity must NOT include safetySettings")
    }

    func testSessionIdPresent() {
        let messages = [LLMMessage(role: .user, content: [.text("hello world")])]
        let result = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-pro", messages: messages, thinking: nil, projectId: "proj"
        )
        let request = result["request"] as? [String: Any]
        let sessionId = request?["sessionId"] as? String
        XCTAssertNotNil(sessionId)
        XCTAssertTrue(sessionId?.hasPrefix("-") == true)
    }

    func testClaudeModelGetsToolConfig() {
        let messages = [LLMMessage(role: .user, content: [.text("hi")])]
        let result = AntigravityRequestBuilder.buildRequest(
            modelName: "claude-sonnet-4-5-20250929", messages: messages, thinking: nil, projectId: "proj"
        )
        let request = result["request"] as? [String: Any]
        let toolConfig = request?["toolConfig"] as? [String: Any]
        let funcConfig = toolConfig?["functionCallingConfig"] as? [String: Any]
        XCTAssertEqual(funcConfig?["mode"] as? String, "VALIDATED")
    }

    func testNonClaudeModelNoToolConfig() {
        let messages = [LLMMessage(role: .user, content: [.text("hi")])]
        let result = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-2.5-pro", messages: messages, thinking: nil, projectId: "proj"
        )
        let request = result["request"] as? [String: Any]
        XCTAssertNil(request?["toolConfig"])
    }
}

import XCTest
@testable import LLMService

final class AntigravityProviderTests: XCTestCase {

    private let testCredentials = LLMCredentials(accessToken: "test-token")

    // MARK: - URL

    func testStreamRequestURL() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        // Fix #1: Must use daily-cloudcode-pa.googleapis.com (not cloudcode-pa.googleapis.com)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://daily-cloudcode-pa.googleapis.com/v1internal:streamGenerateContent?alt=sse",
            "Antigravity streaming URL must use daily-cloudcode-pa.googleapis.com domain"
        )

        // Ensure it does NOT use the non-daily domain
        XCTAssertFalse(
            request.url?.absoluteString.contains("https://cloudcode-pa.googleapis.com") == true,
            "Must NOT use cloudcode-pa.googleapis.com without daily- prefix"
        )
    }

    // MARK: - Headers

    func testStreamRequestContainsRequiredHeaders() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        // Fix #2: Required headers for Antigravity streaming
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "antigravity/1.104.0 darwin/arm64")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept"),
            "text/event-stream",
            "Antigravity streaming requests must include Accept: text/event-stream header"
        )
    }

    func testStreamRequestDoesNotContainGeminiSpecificHeaders() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        // Fix #2: These headers are Gemini-only and must NOT be present in Antigravity
        XCTAssertNil(
            request.value(forHTTPHeaderField: "X-Goog-Api-Client"),
            "Antigravity must NOT include X-Goog-Api-Client header (Gemini-only)"
        )
        XCTAssertNil(
            request.value(forHTTPHeaderField: "Client-Metadata"),
            "Antigravity must NOT include Client-Metadata header (Gemini-only)"
        )
    }

    func testStreamRequestUserAgentDiffersFromGemini() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityUA = antigravityRequest.value(forHTTPHeaderField: "User-Agent")
        let geminiUA = geminiRequest.value(forHTTPHeaderField: "User-Agent")

        XCTAssertEqual(antigravityUA, "antigravity/1.104.0 darwin/arm64")
        XCTAssertEqual(geminiUA, "google-api-nodejs-client/9.15.1")
        XCTAssertNotEqual(
            antigravityUA,
            geminiUA,
            "Antigravity and Gemini must have different User-Agent strings"
        )
    }

    func testStreamRequestAcceptHeaderDiffersFromGeminiNonStream() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildNonStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityAccept = antigravityRequest.value(forHTTPHeaderField: "Accept")
        let geminiAccept = geminiRequest.value(forHTTPHeaderField: "Accept")

        XCTAssertEqual(
            antigravityAccept,
            "text/event-stream",
            "Antigravity streaming must use text/event-stream"
        )
        XCTAssertNotEqual(
            geminiAccept,
            "text/event-stream",
            "Gemini non-streaming should not use text/event-stream"
        )
    }

    // MARK: - Request Body (Antigravity Envelope)

    func testRequestContainsAntigravityEnvelope() throws {
        let provider = AntigravityProvider(projectId: "test-project")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)

        // Verify all envelope fields are present
        XCTAssertNotNil(body["model"], "Envelope must contain 'model' field")
        XCTAssertNotNil(body["userAgent"], "Envelope must contain 'userAgent' field")
        XCTAssertNotNil(body["requestType"], "Envelope must contain 'requestType' field")
        XCTAssertNotNil(body["project"], "Envelope must contain 'project' field")
        XCTAssertNotNil(body["requestId"], "Envelope must contain 'requestId' field")
        XCTAssertNotNil(body["request"], "Envelope must contain nested 'request' field")

        // Verify envelope values
        XCTAssertEqual(body["userAgent"] as? String, "antigravity")
        XCTAssertEqual(body["requestType"] as? String, "agent")

        let requestId = try XCTUnwrap(body["requestId"] as? String)
        XCTAssertTrue(
            requestId.hasPrefix("agent-"),
            "requestId must start with 'agent-' prefix"
        )
    }

    func testRequestContainsProjectField() throws {
        let provider = AntigravityProvider(projectId: "my-project-789")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        XCTAssertEqual(
            body["project"] as? String,
            "my-project-789",
            "Envelope 'project' field must match projectId passed to provider"
        )
    }

    func testRequestContainsModelField() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-flash-thinking",
            messages: [LLMMessage(role: .user, content: [.text("test")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        XCTAssertEqual(
            body["model"] as? String,
            "gemini-2.5-flash-thinking",
            "Envelope 'model' field must match modelId passed to buildStreamRequest"
        )
    }

    func testRequestContainsNestedRequestWithContents() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let nestedRequest = try XCTUnwrap(
            body["request"] as? [String: Any],
            "Envelope must contain nested 'request' dictionary"
        )

        let contents = try XCTUnwrap(
            nestedRequest["contents"] as? [[String: Any]],
            "Nested request must contain 'contents' array"
        )

        XCTAssertFalse(contents.isEmpty, "Contents array must not be empty")
    }

    func testRequestContainsSessionId() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let nestedRequest = try XCTUnwrap(body["request"] as? [String: Any])
        let sessionId = try XCTUnwrap(
            nestedRequest["sessionId"] as? String,
            "Nested request must contain 'sessionId' field"
        )

        XCTAssertTrue(
            sessionId.hasPrefix("-"),
            "sessionId must start with '-' prefix"
        )
    }

    func testRequestDoesNotContainSafetySettings() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let nestedRequest = try XCTUnwrap(body["request"] as? [String: Any])

        XCTAssertNil(
            nestedRequest["safetySettings"],
            "Antigravity requests must NOT include safetySettings (Gemini-only feature)"
        )
    }

    // MARK: - Non-Streaming

    func testNonStreamRequestThrows() throws {
        let provider = AntigravityProvider(projectId: "proj")

        XCTAssertThrowsError(
            try provider.buildNonStreamRequest(
                modelId: "gemini-2.5-pro",
                messages: [LLMMessage(role: .user, content: [.text("hello")])],
                thinking: nil,
                credentials: testCredentials,
                traceId: "test"
            ),
            "buildNonStreamRequest must throw since Antigravity is streaming-only"
        ) { error in
            guard let serviceError = error as? LLMServiceError else {
                XCTFail("Expected LLMServiceError, got \(type(of: error))")
                return
            }
            XCTAssertTrue(
                serviceError.message.contains("non-streaming"),
                "Error message should mention non-streaming is not supported"
            )
        }
    }

    func testSupportsNonStreamingIsFalse() {
        let provider = AntigravityProvider(projectId: "proj")
        XCTAssertFalse(
            provider.supportsNonStreaming,
            "Antigravity is streaming-only, supportsNonStreaming must be false"
        )
    }

    // MARK: - Comparison with Gemini (Regression Tests)

    func testAntigravityAndGeminiUseDifferentDomains() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityURL = try XCTUnwrap(antigravityRequest.url?.absoluteString)
        let geminiURL = try XCTUnwrap(geminiRequest.url?.absoluteString)

        XCTAssertTrue(
            antigravityURL.contains("daily-cloudcode-pa.googleapis.com"),
            "Antigravity must use daily-cloudcode-pa.googleapis.com"
        )
        XCTAssertTrue(
            geminiURL.contains("cloudcode-pa.googleapis.com"),
            "Gemini uses cloudcode-pa.googleapis.com"
        )
        XCTAssertFalse(
            geminiURL.contains("daily-cloudcode-pa.googleapis.com"),
            "Gemini must NOT use daily- prefix"
        )
    }

    func testAntigravityAndGeminiEnvelopesAreDifferent() throws {
        let antigravityProvider = AntigravityProvider(projectId: "proj")
        let antigravityRequest = try antigravityProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let geminiProvider = GeminiCLIProvider(projectId: "proj")
        let geminiRequest = try geminiProvider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let antigravityBody = try parseBody(antigravityRequest)
        let geminiBody = try parseBody(geminiRequest)

        // Antigravity has additional envelope fields
        XCTAssertNotNil(antigravityBody["userAgent"])
        XCTAssertNotNil(antigravityBody["requestType"])
        XCTAssertNotNil(antigravityBody["requestId"])

        let antigravityNestedRequest = antigravityBody["request"] as? [String: Any]
        let geminiNestedRequest = geminiBody["request"] as? [String: Any]

        // Antigravity has sessionId
        XCTAssertNotNil(antigravityNestedRequest?["sessionId"])

        // Gemini has safetySettings, Antigravity does not
        XCTAssertNotNil(geminiNestedRequest?["safetySettings"])
        XCTAssertNil(antigravityNestedRequest?["safetySettings"])
    }

    // MARK: - HTTP Method and Timeout

    func testStreamRequestUsesPostMethod() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testStreamRequestHasTimeout() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        XCTAssertEqual(request.timeoutInterval, 600, "Timeout must be 600 seconds")
    }

    // MARK: - System Instruction Injection

    func testClaudeModelInjectsAntigravitySystemInstruction() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "claude-sonnet-4-5-20250929",
            messages: [
                LLMMessage(role: .system, content: [.text("Be helpful")]),
                LLMMessage(role: .user, content: [.text("hello")]),
            ],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        let sysInstr = try XCTUnwrap(inner["systemInstruction"] as? [String: Any])
        let parts = try XCTUnwrap(sysInstr["parts"] as? [[String: Any]])

        // Must have at least 3 parts: preamble, ignore block, user system msg
        XCTAssertGreaterThanOrEqual(parts.count, 3, "Should have preamble + ignore + user system parts")

        // Part 0: Antigravity preamble
        let preamble = try XCTUnwrap(parts[0]["text"] as? String)
        XCTAssertTrue(preamble.contains("You are Antigravity"), "First part must be Antigravity preamble")

        // Part 1: Ignore block wrapping the preamble
        let ignoreBlock = try XCTUnwrap(parts[1]["text"] as? String)
        XCTAssertTrue(ignoreBlock.hasPrefix("Please ignore following [ignore]"), "Second part must be ignore block")
        XCTAssertTrue(ignoreBlock.hasSuffix("[/ignore]"), "Ignore block must end with [/ignore]")

        // Part 2: User system message
        let userMsg = try XCTUnwrap(parts[2]["text"] as? String)
        XCTAssertEqual(userMsg, "Be helpful", "User system message should follow injected parts")
    }

    func testGemini3ProHighInjectsAntigravitySystemInstruction() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-3-pro-high",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        let sysInstr = try XCTUnwrap(inner["systemInstruction"] as? [String: Any])
        let parts = try XCTUnwrap(sysInstr["parts"] as? [[String: Any]])

        XCTAssertGreaterThanOrEqual(parts.count, 2, "gemini-3-pro-high must get system instruction injection")
        let preamble = try XCTUnwrap(parts[0]["text"] as? String)
        XCTAssertTrue(preamble.contains("You are Antigravity"))
    }

    func testRegularGeminiModelDoesNotInjectSystemInstruction() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let inner = try XCTUnwrap(body["request"] as? [String: Any])

        if let sysInstr = inner["systemInstruction"] as? [String: Any],
           let parts = sysInstr["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = part["text"] as? String {
                    XCTAssertFalse(
                        text.contains("You are Antigravity"),
                        "Regular Gemini models must NOT get Antigravity system instruction"
                    )
                }
            }
        }
    }

    func testClaudeModelWithNoUserSystemMessages() throws {
        let provider = AntigravityProvider(projectId: "proj")
        let request = try provider.buildStreamRequest(
            modelId: "claude-sonnet-4-5-20250929",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            credentials: testCredentials,
            traceId: "test"
        )

        let body = try parseBody(request)
        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        let sysInstr = try XCTUnwrap(inner["systemInstruction"] as? [String: Any])
        let parts = try XCTUnwrap(sysInstr["parts"] as? [[String: Any]])

        // Exactly 2 parts: preamble + ignore block (no user system messages)
        XCTAssertEqual(parts.count, 2, "With no user system messages, should have exactly preamble + ignore block")
    }

    // MARK: - maxOutputTokens Handling

    func testClaudeModelKeepsMaxOutputTokens() throws {
        let body = AntigravityRequestBuilder.buildRequest(
            modelName: "claude-sonnet-4-5-20250929",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            projectId: "proj",
            maxOutputTokens: 8192
        )

        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        let genConfig = try XCTUnwrap(inner["generationConfig"] as? [String: Any])
        XCTAssertEqual(
            genConfig["maxOutputTokens"] as? Int,
            8192,
            "Claude models should retain maxOutputTokens"
        )
    }

    func testGeminiModelRemovesMaxOutputTokens() throws {
        let body = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            projectId: "proj",
            maxOutputTokens: 8192
        )

        let inner = try XCTUnwrap(body["request"] as? [String: Any])

        if let genConfig = inner["generationConfig"] as? [String: Any] {
            XCTAssertNil(
                genConfig["maxOutputTokens"],
                "Non-Claude models must NOT have maxOutputTokens"
            )
        }
        // generationConfig might be removed entirely if maxOutputTokens was the only field
    }

    func testGeminiModelWithOtherGenConfigKeepsNonMaxFields() throws {
        let body = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            projectId: "proj",
            temperature: 0.7,
            maxOutputTokens: 8192
        )

        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        let genConfig = try XCTUnwrap(inner["generationConfig"] as? [String: Any])

        XCTAssertNil(genConfig["maxOutputTokens"], "maxOutputTokens must be removed for Gemini")
        XCTAssertEqual(genConfig["temperature"] as? Double, 0.7, "Other genConfig fields should be preserved")
    }

    // MARK: - Claude toolConfig

    func testClaudeModelSetsValidatedToolConfig() throws {
        let body = AntigravityRequestBuilder.buildRequest(
            modelName: "claude-sonnet-4-5-20250929",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            projectId: "proj"
        )

        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        let toolConfig = try XCTUnwrap(inner["toolConfig"] as? [String: Any])
        let funcConfig = try XCTUnwrap(toolConfig["functionCallingConfig"] as? [String: Any])
        XCTAssertEqual(funcConfig["mode"] as? String, "VALIDATED")
    }

    func testGeminiModelDoesNotSetToolConfig() throws {
        let body = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            projectId: "proj"
        )

        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        XCTAssertNil(inner["toolConfig"], "Non-Claude models should not have toolConfig")
    }

    // MARK: - Schema Cleaning

    func testSchemaCleanerConvertsConstToEnum() {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "action": [
                    "const": "submit",
                ] as [String: Any],
            ] as [String: Any],
            "required": ["action"],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        let props = cleaned["properties"] as! [String: Any]
        let action = props["action"] as! [String: Any]

        XCTAssertNil(action["const"], "const should be removed")
        XCTAssertEqual(action["enum"] as? [String], ["submit"], "const should become enum with one value")
        XCTAssertEqual(action["type"] as? String, "string", "type should be set to string for enum")
    }

    func testSchemaCleanerRemovesUnsupportedKeywords() {
        let schema: [String: Any] = [
            "type": "object",
            "$schema": "http://json-schema.org/draft-07/schema#",
            "additionalProperties": false,
            "properties": [
                "name": [
                    "type": "string",
                    "minLength": 1,
                    "maxLength": 100,
                    "pattern": "^[a-z]+$",
                    "title": "Name Field",
                ] as [String: Any],
            ] as [String: Any],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)

        XCTAssertNil(cleaned["$schema"], "$schema should be removed")
        XCTAssertNil(cleaned["additionalProperties"], "additionalProperties should be removed")

        let props = cleaned["properties"] as! [String: Any]
        let name = props["name"] as! [String: Any]

        XCTAssertNil(name["minLength"], "minLength should be removed")
        XCTAssertNil(name["maxLength"], "maxLength should be removed")
        XCTAssertNil(name["pattern"], "pattern should be removed")
    }

    func testSchemaCleanerAddsPlaceholderToEmptyObject() throws {
        let schema: [String: Any] = [
            "type": "object",
        ]

        let cleaned = AntigravitySchemaCleaner.addEmptySchemaPlaceholders(schema)
        let props = try XCTUnwrap(cleaned["properties"] as? [String: Any])
        let reason = try XCTUnwrap(props["reason"] as? [String: Any])

        XCTAssertEqual(reason["type"] as? String, "string")
        XCTAssertNotNil(reason["description"])
        XCTAssertEqual(cleaned["required"] as? [String], ["reason"])
    }

    func testSchemaCleanerSkipsUnderscorePlaceholderAtTopLevel() {
        // Top-level schemas with properties but no required should NOT get "_" placeholder
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"] as [String: Any],
            ] as [String: Any],
        ]

        let cleaned = AntigravitySchemaCleaner.addEmptySchemaPlaceholders(schema, isTopLevel: true)
        let props = cleaned["properties"] as! [String: Any]
        XCTAssertNil(props["_"], "Top-level schema should not get _ placeholder")
        XCTAssertNil(cleaned["required"], "Top-level schema should not get required added")
    }

    func testSchemaCleanerAddsUnderscorePlaceholderForNoRequiredProps() {
        // Non-top-level schemas with properties but no required should get "_" placeholder
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"] as [String: Any],
            ] as [String: Any],
            // No "required" field
        ]

        let cleaned = AntigravitySchemaCleaner.addEmptySchemaPlaceholders(schema, isTopLevel: false)
        let props = cleaned["properties"] as! [String: Any]

        XCTAssertNotNil(props["_"], "Should add _ placeholder property")
        XCTAssertEqual(cleaned["required"] as? [String], ["_"])
    }

    func testSchemaCleanerFlattensTypeArray() {
        let schema: [String: Any] = [
            "type": ["string", "null"] as [Any],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        XCTAssertEqual(cleaned["type"] as? String, "string", "Type array should be flattened to first non-null")
    }

    func testSchemaCleanerMergesAllOf() {
        let schema: [String: Any] = [
            "allOf": [
                [
                    "properties": ["a": ["type": "string"]] as [String: Any],
                    "required": ["a"],
                ] as [String: Any],
                [
                    "properties": ["b": ["type": "integer"]] as [String: Any],
                    "required": ["b"],
                ] as [String: Any],
            ] as [[String: Any]],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)

        XCTAssertNil(cleaned["allOf"], "allOf should be removed after merging")
        let props = cleaned["properties"] as! [String: Any]
        XCTAssertNotNil(props["a"], "Property 'a' should be merged")
        XCTAssertNotNil(props["b"], "Property 'b' should be merged")
        let required = cleaned["required"] as! [String]
        XCTAssertTrue(required.contains("a"))
        XCTAssertTrue(required.contains("b"))
    }

    func testSchemaCleanerRemovesExtensionFields() {
        let schema: [String: Any] = [
            "type": "string",
            "x-google-enum-descriptions": ["one", "two"],
            "x-custom": "value",
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        XCTAssertNil(cleaned["x-google-enum-descriptions"])
        XCTAssertNil(cleaned["x-custom"])
    }

    func testSchemaCleanerMovesConstraintsToDescription() {
        let schema: [String: Any] = [
            "type": "string",
            "minLength": 1,
            "maxLength": 50,
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        let desc = cleaned["description"] as? String

        XCTAssertNotNil(desc, "Constraints should be moved to description")
        XCTAssertTrue(desc?.contains("minLength") ?? false)
        XCTAssertTrue(desc?.contains("maxLength") ?? false)
    }

    func testCleanFunctionDeclarationsCleansTool() {
        let tools: [[String: Any]] = [
            [
                "name": "my_tool",
                "description": "A test tool",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "mode": ["const": "fast"] as [String: Any],
                    ] as [String: Any],
                    "$schema": "http://json-schema.org/draft-07/schema#",
                ] as [String: Any],
            ] as [String: Any],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanFunctionDeclarations(tools)

        let params = cleaned[0]["parameters"] as! [String: Any]
        XCTAssertNil(params["$schema"], "$schema should be removed from tool parameters")
        let props = params["properties"] as! [String: Any]
        let mode = props["mode"] as! [String: Any]
        XCTAssertNil(mode["const"])
        XCTAssertNotNil(mode["enum"])
    }

    func testSchemaCleanerConvertsRefToHint() {
        let schema: [String: Any] = [
            "$ref": "#/definitions/MyType",
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)

        XCTAssertNil(cleaned["$ref"], "$ref should be removed")
        let desc = cleaned["description"] as? String
        XCTAssertEqual(desc, "See: MyType", "$ref should be converted to description hint")
        XCTAssertEqual(cleaned["type"] as? String, "object", "Should default to object type")
    }

    func testSchemaCleanerAddsEnumHints() {
        let schema: [String: Any] = [
            "type": "string",
            "enum": ["red", "green", "blue"],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        let desc = cleaned["description"] as? String

        XCTAssertNotNil(desc)
        XCTAssertTrue(desc?.contains("Allowed:") ?? false, "Should contain enum hint")
        XCTAssertTrue(desc?.contains("red") ?? false)
    }

    func testSchemaCleanerAddsAdditionalPropertiesHint() {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        let desc = cleaned["description"] as? String

        XCTAssertNotNil(desc)
        XCTAssertTrue(desc?.contains("No extra properties allowed") ?? false)
        XCTAssertNil(cleaned["additionalProperties"], "additionalProperties should be removed")
    }

    func testGeminiCleaningRemovesNullableAndTitle() {
        let tools: [[String: Any]] = [
            [
                "name": "tool",
                "description": "A tool",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "name": [
                            "type": "string",
                            "nullable": true,
                            "title": "Name Field",
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanFunctionDeclarationsForGemini(tools)
        let params = cleaned[0]["parameters"] as! [String: Any]
        let props = params["properties"] as! [String: Any]
        let name = props["name"] as! [String: Any]

        XCTAssertNil(name["nullable"], "Gemini cleaning should remove nullable")
        XCTAssertNil(name["title"], "Gemini cleaning should remove title")
    }

    func testGeminiModelAlsoGetsSchemaCleaned() throws {
        // Non-Antigravity-schema models should still get Gemini schema cleaning
        let tools: [[String: Any]] = [
            [
                "name": "tool",
                "parameters": [
                    "type": "object",
                    "$schema": "http://json-schema.org/draft-07/schema#",
                    "properties": [
                        "x": ["type": "string", "nullable": true] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]

        let body = AntigravityRequestBuilder.buildRequest(
            modelName: "gemini-2.5-pro",
            messages: [LLMMessage(role: .user, content: [.text("hello")])],
            thinking: nil,
            projectId: "proj",
            tools: tools
        )

        let inner = try XCTUnwrap(body["request"] as? [String: Any])
        let toolsArr = try XCTUnwrap(inner["tools"] as? [[String: Any]])
        let funcDecls = try XCTUnwrap(toolsArr[0]["functionDeclarations"] as? [[String: Any]])
        let params = try XCTUnwrap(funcDecls[0]["parameters"] as? [String: Any])

        XCTAssertNil(params["$schema"], "Gemini models should also get schema cleaned")
        let props = try XCTUnwrap(params["properties"] as? [String: Any])
        let x = try XCTUnwrap(props["x"] as? [String: Any])
        XCTAssertNil(x["nullable"], "Gemini cleaning should remove nullable")
    }

    func testSchemaCleanerHandlesNullableTypeArray() {
        // A property with type ["string", "null"] should be flattened and marked nullable
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "name": [
                    "type": ["string", "null"] as [Any],
                ] as [String: Any],
            ] as [String: Any],
            "required": ["name"],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        let props = cleaned["properties"] as! [String: Any]
        let name = props["name"] as! [String: Any]

        XCTAssertEqual(name["type"] as? String, "string", "Should flatten to first non-null type")
        let desc = name["description"] as? String ?? ""
        XCTAssertTrue(desc.contains("nullable"), "Should add (nullable) hint")

        // Nullable field should be removed from required
        if let required = cleaned["required"] as? [String] {
            XCTAssertFalse(required.contains("name"), "Nullable fields should be removed from required")
        }
    }

    func testSchemaCleanerAddsAcceptsHintForMultiTypeArray() {
        let schema: [String: Any] = [
            "type": ["string", "integer"] as [Any],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)
        let desc = cleaned["description"] as? String ?? ""

        XCTAssertTrue(desc.contains("Accepts:"), "Should add Accepts: hint for multi-type")
        XCTAssertTrue(desc.contains("string"), "Should list string type")
        XCTAssertTrue(desc.contains("integer"), "Should list integer type")
    }

    func testSchemaCleanerRefReplacesEntireSchema() {
        let schema: [String: Any] = [
            "$ref": "#/definitions/MyType",
            "nullable": true,
            "title": "My Title",
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)

        // $ref should replace entire schema, discarding sibling keys
        XCTAssertNil(cleaned["$ref"])
        XCTAssertNil(cleaned["nullable"], "Sibling keys should be discarded when $ref is replaced")
        XCTAssertNil(cleaned["title"], "Sibling keys should be discarded when $ref is replaced")
        XCTAssertEqual(cleaned["type"] as? String, "object")
        XCTAssertEqual(cleaned["description"] as? String, "See: MyType")
    }

    func testSchemaCleanerAnyOfAddsAcceptsHint() {
        let schema: [String: Any] = [
            "anyOf": [
                ["type": "string"] as [String: Any],
                ["type": "object", "properties": ["x": ["type": "integer"]]] as [String: Any],
            ] as [[String: Any]],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanSchema(schema)

        XCTAssertNil(cleaned["anyOf"], "anyOf should be removed")
        // Object should be selected (more complex)
        XCTAssertEqual(cleaned["type"] as? String, "object")
        let desc = cleaned["description"] as? String ?? ""
        XCTAssertTrue(desc.contains("Accepts:"), "Should add Accepts: hint")
        XCTAssertTrue(desc.contains("string"))
        XCTAssertTrue(desc.contains("object"))
    }

    func testGeminiCleaningDoesNotAddPlaceholders() {
        let tools: [[String: Any]] = [
            [
                "name": "tool",
                "parameters": [
                    "type": "object",
                ] as [String: Any],
            ] as [String: Any],
        ]

        let cleaned = AntigravitySchemaCleaner.cleanFunctionDeclarationsForGemini(tools)
        let params = cleaned[0]["parameters"] as! [String: Any]

        // Gemini cleaning should NOT add "reason" placeholder
        XCTAssertNil(
            params["properties"],
            "Gemini cleaning should not add placeholder properties to empty objects"
        )
        XCTAssertNil(
            params["required"],
            "Gemini cleaning should not add required fields to empty objects"
        )
    }

    // MARK: - Helpers

    private func parseBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

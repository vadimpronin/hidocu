# LLMService

A Swift Package that provides a unified async/await interface for interacting with LLM providers. It reverse-engineers CLI-based APIs (Gemini CLI, Antigravity, Claude Code) and exposes them as standard Swift APIs with streaming, thinking, tool use, prompt caching, and OAuth built in.

**Platforms:** iOS 16+, macOS 13+ &mdash; **Swift:** 5.9+ &mdash; **Dependencies:** None (Apple frameworks only)

## Installation

Add LLMService to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/LLMService.git", from: "1.0.0")
]
```

Or in Xcode: File > Add Package Dependencies and paste the repository URL.

```swift
import LLMService
```

## Quick Start

```swift
// 1. Create a session (you implement LLMAccountSession — see "Sessions" below)
let session = MyAccountSession(provider: .claudeCode)

// 2. Create the service
let service = LLMService(session: session)

// 3. Log in via OAuth (opens browser)
try await service.login()

// 4. Send a message
let response = try await service.chat(
    modelId: "claude-sonnet-4-5-20250929",
    messages: [
        LLMMessage(role: .user, content: [.text("Explain quantum computing in one paragraph.")])
    ]
)

print(response.fullText)
// => "Quantum computing leverages the principles of quantum mechanics..."

print(response.usage?.totalTokens ?? 0)
// => 342
```

## Providers

LLMService supports three providers, each with its own OAuth flow and API format:

| Provider | Enum Value | Models | Streaming | Non-Streaming |
|---|---|---|---|---|
| **Claude Code** | `.claudeCode` | Claude Sonnet 4.5, Opus 4.6, Haiku 4.5 | Yes | Yes |
| **Gemini CLI** | `.geminiCLI` | Gemini 2.5 Pro, 2.5 Flash, 2.0 Flash | Yes | Yes |
| **Antigravity** | `.antigravity` | Gemini 2.5 Pro/Flash, Claude Sonnet 4.5 | Yes | No |

The provider is determined by the session you pass in. All API differences (headers, request format, response parsing, OAuth) are handled internally.

## Core API

### `chat()` — Non-Streaming

Sends messages and returns a complete `LLMResponse`. Internally uses streaming and aggregates the chunks.

```swift
let response = try await service.chat(
    modelId: "claude-sonnet-4-5-20250929",
    messages: [
        LLMMessage(role: .system, content: [.text("You are a helpful assistant.")]),
        LLMMessage(role: .user, content: [.text("What is the capital of France?")])
    ]
)

// Full text of the response (concatenated text parts)
print(response.fullText) // "The capital of France is Paris."

// Structured parts — may include thinking, text, and tool calls
for part in response.content {
    switch part {
    case .text(let str):
        print("Text: \(str)")
    case .thinking(let str):
        print("Thinking: \(str)")
    case .toolCall(let id, let function, let arguments):
        print("Tool call: \(function)(\(arguments))")
    }
}

// Token usage
if let usage = response.usage {
    print("Input: \(usage.inputTokens), Output: \(usage.outputTokens), Total: \(usage.totalTokens)")
}
```

### `chatStream()` — Streaming

Returns an `AsyncThrowingStream<LLMChatChunk, Error>` for real-time token-by-token output.

```swift
let stream = service.chatStream(
    modelId: "gemini-2.5-pro",
    messages: [
        LLMMessage(role: .user, content: [.text("Write a haiku about Swift.")])
    ]
)

for try await chunk in stream {
    switch chunk.partType {
    case .text:
        print(chunk.delta, terminator: "") // Print tokens as they arrive

    case .thinking:
        print("[thinking] \(chunk.delta)", terminator: "")

    case .toolCall(let id, let function):
        print("[tool:\(function)] \(chunk.delta)", terminator: "")
    }

    // Final chunk carries usage info
    if let usage = chunk.usage {
        print("\n--- \(usage.totalTokens) tokens ---")
    }
}
```

## Messages and Content

### LLMMessage

Every request is an array of `LLMMessage` values. Each message has a role and one or more content blocks.

```swift
LLMMessage(role: .system, content: [.text("System prompt here")])
LLMMessage(role: .user, content: [.text("User question")])
LLMMessage(role: .assistant, content: [.text("Previous assistant reply")])
LLMMessage(role: .tool, content: [.text("Tool result JSON")])
```

### LLMContent

Content blocks within a message. Supports text, thinking, files, and raw binary data.

```swift
// Plain text
.text("Hello, world!")

// Thinking block (for multi-turn conversations with thinking)
.thinking("Let me analyze this step by step...", signature: "cached_sig_value")

// File reference (auto-detected as image, audio, video, or text)
.file(URL(fileURLWithPath: "/path/to/image.png"))

// Raw binary data with MIME type
.fileContent(imageData, mimeType: "image/png", filename: "chart.png")
```

## Multi-Turn Conversations

Build up conversation history by passing previous messages:

```swift
var messages: [LLMMessage] = [
    LLMMessage(role: .system, content: [.text("You are a math tutor.")]),
    LLMMessage(role: .user, content: [.text("What is 2 + 2?")])
]

let first = try await service.chat(modelId: "claude-sonnet-4-5-20250929", messages: messages)
print(first.fullText) // "2 + 2 equals 4."

// Append assistant reply and new user message
messages.append(LLMMessage(role: .assistant, content: [.text(first.fullText)]))
messages.append(LLMMessage(role: .user, content: [.text("Now multiply that by 3.")]))

let second = try await service.chat(modelId: "claude-sonnet-4-5-20250929", messages: messages)
print(second.fullText) // "4 multiplied by 3 equals 12."
```

## Thinking (Extended Reasoning)

Enable the model's internal reasoning process. The thinking output is returned alongside the text response.

```swift
// Fixed budget — allocate a specific number of tokens for thinking
let response = try await service.chat(
    modelId: "claude-sonnet-4-5-20250929",
    messages: [
        LLMMessage(role: .user, content: [.text("Prove that the square root of 2 is irrational.")])
    ],
    thinking: .enabled(budgetTokens: 4096)
)

// Adaptive — let the model decide how much to think
let response2 = try await service.chat(
    modelId: "gemini-2.5-pro",
    messages: [
        LLMMessage(role: .user, content: [.text("Design a distributed cache.")])
    ],
    thinking: .adaptive
)

// Access thinking output
for part in response.content {
    switch part {
    case .thinking(let thought):
        print("Model reasoning:\n\(thought)")
    case .text(let answer):
        print("Final answer:\n\(answer)")
    default:
        break
    }
}
```

### Thinking in Multi-Turn Conversations

When continuing a conversation that included thinking, pass the thinking content back so the model retains context:

```swift
// After a response that included thinking, build the assistant message with both parts
var assistantContent: [LLMContent] = []

for part in response.content {
    switch part {
    case .thinking(let thought):
        assistantContent.append(.thinking(thought, signature: nil))
    case .text(let text):
        assistantContent.append(.text(text))
    default:
        break
    }
}

messages.append(LLMMessage(role: .assistant, content: assistantContent))
messages.append(LLMMessage(role: .user, content: [.text("Can you elaborate on step 3?")]))
```

## Images and Files

### Inline Image

```swift
let imageData = try Data(contentsOf: URL(fileURLWithPath: "photo.jpg"))

let response = try await service.chat(
    modelId: "claude-sonnet-4-5-20250929",
    messages: [
        LLMMessage(role: .user, content: [
            .text("Describe what you see in this image."),
            .fileContent(imageData, mimeType: "image/jpeg", filename: "photo.jpg")
        ])
    ]
)
```

### File Reference

```swift
let response = try await service.chat(
    modelId: "gemini-2.5-pro",
    messages: [
        LLMMessage(role: .user, content: [
            .text("Summarize this document."),
            .file(URL(fileURLWithPath: "/path/to/report.pdf"))
        ])
    ]
)
```

File references are automatically processed: images are base64-encoded, text files are inlined with filename headers, and binary files are sent as base64 with their detected MIME type.

## Model Discovery

List available models for the current provider with capability metadata:

```swift
let models = try await service.listModels()

for model in models {
    print("""
    \(model.displayName) (\(model.id))
      Text: \(model.supportsText), Images: \(model.supportsImage)
      Thinking: \(model.supportsThinking), Tools: \(model.supportsTools)
      Max input: \(model.maxInputTokens ?? 0), Max output: \(model.maxOutputTokens ?? 0)
    """)
}
```

Example output for Claude Code:

```
Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)
  Text: true, Images: true
  Thinking: true, Tools: true
  Max input: 200000, Max output: 16384

Claude Opus 4.6 (claude-opus-4-6)
  Text: true, Images: true
  Thinking: true, Tools: true
  Max input: 200000, Max output: 16384

Claude Haiku 4.5 (claude-haiku-4-5-20251001)
  Text: true, Images: true
  Thinking: true, Tools: true
  Max input: 200000, Max output: 16384
```

## Rate Limits and Quota

After making at least one request, query the rate limit status parsed from response headers:

```swift
// Make a request first (headers are captured automatically)
let _ = try await service.chat(
    modelId: "claude-sonnet-4-5-20250929",
    messages: [LLMMessage(role: .user, content: [.text("ping")])]
)

// Check quota
let quota = try await service.getQuotaStatus(for: "claude-sonnet-4-5-20250929")

print("Available: \(quota.isAvailable)")
print("Remaining requests: \(quota.remainingRequests ?? -1)")

if let reset = quota.resetIn {
    print("Resets in: \(reset) seconds")
}
```

## Sessions

You must implement `LLMAccountSession` to manage account info and credential persistence. This is how LLMService knows which provider to use and where to store tokens.

```swift
public protocol LLMAccountSession: AnyObject, Sendable {
    var info: LLMAccountInfo { get }
    func getCredentials() async throws -> LLMCredentials
    func save(info: LLMAccountInfo, credentials: LLMCredentials) async throws
}
```

### Example Implementation

```swift
final class MyAccountSession: LLMAccountSession, @unchecked Sendable {
    let info: LLMAccountInfo
    private var credentials: LLMCredentials?

    init(provider: LLMProvider) {
        self.info = LLMAccountInfo(provider: provider)
    }

    func getCredentials() async throws -> LLMCredentials {
        guard let creds = credentials else {
            throw LLMServiceError(traceId: "", message: "Not logged in")
        }
        return creds
    }

    func save(info: LLMAccountInfo, credentials: LLMCredentials) async throws {
        self.credentials = credentials
        // Persist to Keychain, UserDefaults, file, etc.
    }
}
```

### LLMAccountInfo

```swift
let info = LLMAccountInfo(
    provider: .claudeCode,          // Which provider to use
    appUniqueKey: "my-app",         // Optional app identifier
    identifier: "user@example.com", // Optional user identifier
    displayName: "John's Account",  // Optional display name
    metadata: ["project_id": "abc"] // Provider-specific metadata (Antigravity needs "project_id")
)
```

### LLMCredentials

```swift
let credentials = LLMCredentials(
    apiKey: nil,                    // Direct API key (if not using OAuth)
    accessToken: "eyJ...",          // OAuth access token
    refreshToken: "dGhpcyBpcw..",  // OAuth refresh token
    expiresAt: Date().addingTimeInterval(3600) // Token expiry
)
```

## Authentication

LLMService handles the full OAuth flow for each provider. Call `login()` to open the system browser for authentication:

```swift
let service = LLMService(session: session)

do {
    try await service.login()
    print("Logged in as: \(session.info.displayName ?? "unknown")")
} catch {
    print("Login failed: \(error)")
}
```

Token refresh is automatic. When a token expires, LLMService refreshes it before the next request. If a request returns 401, it retries with a fresh token.

### Provider-Specific Auth Details

| Provider | OAuth Type | Token Exchange |
|---|---|---|
| **Claude Code** | PKCE (S256) | JSON body |
| **Gemini CLI** | Standard OAuth | Form-encoded |
| **Antigravity** | Standard OAuth | Form-encoded |

## Prompt Caching (Claude)

Prompt caching is **automatic** for Claude requests. LLMService injects up to 3 `cache_control` breakpoints into every request to optimize cost (up to 90% savings on cached tokens):

1. **Tools** &mdash; last tool definition gets `cache_control`
2. **System prompt** &mdash; last system part gets `cache_control`
3. **Messages** &mdash; second-to-last user message's last content block gets `cache_control`

This mirrors the behavior of the official Claude CLI. If any `cache_control` is already present in the request, auto-injection is skipped entirely.

No code changes are needed to benefit from caching. It works out of the box.

## Thought Signatures (Gemini / Antigravity)

When using thinking with Gemini/Antigravity providers, the API returns `thoughtSignature` values on thinking blocks. These signatures must be replayed in subsequent turns to maintain thinking context.

LLMService handles this transparently:

- **Response side:** Signatures from streamed thinking blocks are automatically cached in an actor-backed `ThoughtSignatureCache` with a 3-hour TTL.
- **Request side:** When you include `.thinking(text, signature:)` content in assistant messages, the signature is sent as `thoughtSignature` on the corresponding part.
- **Sentinel fallback:** For Gemini models, if no cached signature is found, the sentinel value `"skip_thought_signature_validator"` is used automatically.

```swift
// Signatures are cached automatically during streaming.
// When building multi-turn conversations with thinking, just include the thinking content:
let assistantContent: [LLMContent] = [
    .thinking("My analysis...", signature: cachedSignatureOrNil),
    .text("Here is my answer.")
]
```

## Error Handling

All errors are thrown as `LLMServiceError`:

```swift
do {
    let response = try await service.chat(
        modelId: "claude-sonnet-4-5-20250929",
        messages: [LLMMessage(role: .user, content: [.text("Hello")])]
    )
} catch let error as LLMServiceError {
    print("Trace ID: \(error.traceId)")        // Unique request identifier
    print("Message: \(error.message)")          // Human-readable error description
    print("Status: \(error.statusCode ?? 0)")   // HTTP status code (if applicable)
}
```

## Logging and Debugging

LLMService includes built-in trace logging that can export to HAR format for debugging.

### Configuration

```swift
let loggingConfig = LLMLoggingConfig(
    subsystem: "com.myapp.llm",                           // OSLog subsystem
    storageDirectory: URL(fileURLWithPath: "/tmp/logs"),   // Where to store trace files
    shouldMaskTokens: true                                 // Redact auth tokens in logs
)

let service = LLMService(session: session, loggingConfig: loggingConfig)
```

### Export HAR

```swift
// Export the last 30 minutes of request/response traces
let harData = try await service.exportHAR(lastMinutes: 30)
try harData.write(to: URL(fileURLWithPath: "traces.har"))
// Open traces.har in Chrome DevTools, Charles Proxy, etc.
```

### Cleanup

```swift
// Delete trace logs older than 7 days
try await service.cleanupLogs(olderThanDays: 7)
```

## Testing

LLMService is designed for testability via protocol-based dependency injection. Three mock implementations are provided:

- `MockHTTPClient` &mdash; queue responses and capture requests
- `MockAccountSession` &mdash; in-memory credential storage
- `MockOAuthLauncher` &mdash; simulate OAuth callbacks

```swift
// In your test:
let mockHTTP = MockHTTPClient()
let mockSession = MockAccountSession(provider: .claudeCode)
let mockLauncher = MockOAuthLauncher()

let service = LLMService(
    session: mockSession,
    loggingConfig: LLMLoggingConfig(),
    httpClient: mockHTTP,
    oauthLauncher: mockLauncher
)

// Queue a mock streaming response, then call service.chat() or service.chatStream()
```

### Running Tests

```bash
swift test
```

46 tests across 12 test suites covering request building, stream parsing, auth flows, smart chat aggregation, prompt caching, thought signatures, and more.

## Architecture Overview

```
LLMService (public API)
├── login()          → OAuthCoordinator → per-provider auth
├── chat()           → chatStream() → aggregate chunks → LLMResponse
├── chatStream()     → resolveProvider() → InternalProvider
│                       ├── buildStreamRequest()  → Translator builds JSON, Provider adds headers
│                       └── parseStreamLine()     → StreamParser state machine → [LLMChatChunk]
├── listModels()     → static model registry per provider
└── getQuotaStatus() → parsed rate limit headers from last response
```

### Directory Structure

```
Sources/LLMService/
├── Models/          LLMProvider, LLMMessage, LLMContent, LLMResponse, LLMChatChunk,
│                    LLMModelInfo, LLMQuotaStatus, ThinkingConfig, LLMUsage, LLMServiceError
├── Protocols/       HTTPClient, LLMAccountSession, OAuthSessionLauncher
├── Auth/            OAuthCoordinator, ClaudeCodeAuthProvider, GoogleOAuthProvider,
│                    TokenRefresher, PKCEGenerator
├── Translators/     ClaudeRequestBuilder, ClaudeResponseParser, ClaudeStreamParser,
│                    GoogleCloudRequestBuilder, GoogleCloudResponseParser, GoogleCloudStreamParser,
│                    ThoughtSignatureCache, ContentProcessor, SafetySettings
├── Providers/       InternalProvider protocol, ClaudeCodeProvider, GeminiCLIProvider,
│                    AntigravityProvider
├── Networking/      URLSessionHTTPClient, SystemOAuthLauncher, AnyAsyncSequence
├── Logging/         LLMTraceManager, LLMRedactor, HARExporter, LLMLoggingConfig, LLMTraceEntry
└── LLMService.swift Public entry point
```

## API Reference

### LLMService

| Method | Description |
|---|---|
| `init(session:loggingConfig:)` | Create with default HTTP client and OAuth launcher |
| `login()` | Perform OAuth login (opens system browser) |
| `chat(modelId:messages:thinking:idempotencyKey:)` | Send messages, get complete response |
| `chatStream(modelId:messages:thinking:idempotencyKey:)` | Send messages, get streaming chunks |
| `listModels()` | Get available models with capability metadata |
| `getQuotaStatus(for:)` | Get rate limit info from last response headers |
| `exportHAR(lastMinutes:)` | Export recent traces as HAR data |
| `cleanupLogs(olderThanDays:)` | Delete old trace logs |

### Models

| Type | Description |
|---|---|
| `LLMProvider` | `.claudeCode`, `.geminiCLI`, `.antigravity` |
| `LLMMessage` | Message with role (`.system`, `.user`, `.assistant`, `.tool`) and content |
| `LLMContent` | `.text(String)`, `.thinking(String, signature:)`, `.file(URL)`, `.fileContent(Data, mimeType:, filename:)` |
| `LLMResponse` | Complete response with `id`, `model`, `content: [LLMResponsePart]`, `usage`, `fullText` |
| `LLMResponsePart` | `.thinking(String)`, `.text(String)`, `.toolCall(id:, function:, arguments:)` |
| `LLMChatChunk` | Streaming chunk with `id`, `partType: LLMPartTypeDelta`, `delta`, `usage` |
| `LLMPartTypeDelta` | `.thinking`, `.text`, `.toolCall(id:, function:)` |
| `LLMUsage` | `inputTokens`, `outputTokens`, `totalTokens` |
| `LLMModelInfo` | Model metadata: capabilities, token limits |
| `LLMQuotaStatus` | Rate limit status: `isAvailable`, `remainingRequests`, `resetIn` |
| `ThinkingConfig` | `.enabled(budgetTokens:)`, `.adaptive`, `.disabled` |
| `LLMServiceError` | Error with `traceId`, `message`, `statusCode` |
| `LLMAccountInfo` | Account metadata: `provider`, `identifier`, `metadata` |
| `LLMCredentials` | Auth tokens: `apiKey`, `accessToken`, `refreshToken`, `expiresAt` |

### Protocols

| Protocol | Description |
|---|---|
| `LLMAccountSession` | Owns account info and credentials. You implement this. |
| `HTTPClient` | `data(for:)` and `bytes(for:)`. Default: `URLSessionHTTPClient`. |
| `OAuthSessionLauncher` | Opens system browser for OAuth. Default: `SystemOAuthLauncher`. |

## License

See [LICENSE](LICENSE) for details.

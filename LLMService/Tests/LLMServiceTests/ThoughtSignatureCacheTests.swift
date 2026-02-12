import XCTest
@testable import LLMService

final class ThoughtSignatureCacheTests: XCTestCase {

    func testCacheAndRetrieve() async {
        let cache = ThoughtSignatureCache()
        let sig = String(repeating: "a", count: 60) // > minValidLength

        await cache.cache(modelName: "gemini-2.5-pro", thinkingText: "some thinking", signature: sig)
        let result = await cache.getCachedSignature(modelName: "gemini-2.5-pro", thinkingText: "some thinking")
        XCTAssertEqual(result, sig)
    }

    func testSentinelForGeminiWhenNoCache() async {
        let cache = ThoughtSignatureCache()
        let result = await cache.getCachedSignature(modelName: "gemini-2.5-pro", thinkingText: "uncached text")
        XCTAssertEqual(result, ThoughtSignatureCache.sentinel)
    }

    func testNilForClaudeWhenNoCache() async {
        let cache = ThoughtSignatureCache()
        let result = await cache.getCachedSignature(modelName: "claude-sonnet-4-5", thinkingText: "uncached text")
        XCTAssertNil(result)
    }

    func testMinValidLength() {
        // Too short
        XCTAssertFalse(ThoughtSignatureCache.isValid("short"))
        XCTAssertFalse(ThoughtSignatureCache.isValid(""))

        // Sentinel is always valid
        XCTAssertTrue(ThoughtSignatureCache.isValid(ThoughtSignatureCache.sentinel))

        // 50+ chars is valid
        let longSig = String(repeating: "x", count: 50)
        XCTAssertTrue(ThoughtSignatureCache.isValid(longSig))
    }

    func testModelGroup() {
        XCTAssertEqual(ThoughtSignatureCache.modelGroup("gemini-2.5-pro"), "gemini")
        XCTAssertEqual(ThoughtSignatureCache.modelGroup("gemini-2.0-flash"), "gemini")
        XCTAssertEqual(ThoughtSignatureCache.modelGroup("claude-sonnet-4-5"), "claude")
        XCTAssertEqual(ThoughtSignatureCache.modelGroup("claude-opus-4-6"), "claude")
        XCTAssertEqual(ThoughtSignatureCache.modelGroup("some-other-model"), "unknown")
    }

    func testDifferentModelsSameGroupShareCache() async {
        let cache = ThoughtSignatureCache()
        let sig = String(repeating: "b", count: 60)

        // Cache with one gemini model
        await cache.cache(modelName: "gemini-2.5-pro", thinkingText: "thinking", signature: sig)

        // Retrieve with different gemini model — same group → same key
        let result = await cache.getCachedSignature(modelName: "gemini-2.5-flash", thinkingText: "thinking")
        // They share the same model group "gemini", so same key
        XCTAssertEqual(result, sig)
    }
}

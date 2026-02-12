import XCTest
@testable import LLMService

final class RedactorTests: XCTestCase {
    func testRedactAuthorizationHeader() {
        let headers = ["Authorization": "Bearer sk-secret-key-123", "Content-Type": "application/json"]
        let redacted = LLMRedactor.redactHeaders(headers)

        XCTAssertTrue(redacted["Authorization"]!.hasPrefix("REDACTED ("))
        XCTAssertEqual(redacted["Content-Type"], "application/json")
    }

    func testRedactAPIKeyHeader() {
        let headers = ["api-key": "my-secret-key"]
        let redacted = LLMRedactor.redactHeaders(headers)
        XCTAssertTrue(redacted["api-key"]!.hasPrefix("REDACTED ("))
    }

    func testRedactJSONBody() {
        let body: [String: Any] = ["access_token": "secret123", "data": "visible"]
        let data = try! JSONSerialization.data(withJSONObject: body)
        let redacted = LLMRedactor.redactJSONBody(data)

        let parsed = try! JSONSerialization.jsonObject(with: redacted) as! [String: Any]
        XCTAssertTrue((parsed["access_token"] as! String).hasPrefix("REDACTED ("))
        XCTAssertEqual(parsed["data"] as? String, "visible")
    }

    func testConsistentRedaction() {
        let headers1 = ["Authorization": "Bearer same-token"]
        let headers2 = ["Authorization": "Bearer same-token"]
        let redacted1 = LLMRedactor.redactHeaders(headers1)
        let redacted2 = LLMRedactor.redactHeaders(headers2)

        // Same token should produce same redacted suffix
        XCTAssertEqual(redacted1["Authorization"], redacted2["Authorization"])
    }
}

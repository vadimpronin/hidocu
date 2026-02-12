import XCTest
@testable import LLMService

final class HARExporterTests: XCTestCase {
    func testExportEmptyEntries() throws {
        let data = try HARExporter.export(entries: [])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let log = json["log"] as! [String: Any]
        XCTAssertEqual(log["version"] as? String, "1.2")
        let entries = log["entries"] as! [[String: Any]]
        XCTAssertTrue(entries.isEmpty)
    }

    func testExportWithEntry() throws {
        let entry = LLMTraceEntry(
            traceId: "trace-1",
            requestId: "req-1",
            timestamp: Date(),
            provider: "claudeCode",
            accountIdentifier: "test@test.com",
            method: "chat",
            isStreaming: false,
            request: LLMTraceEntry.HTTPDetails(
                url: "https://api.anthropic.com/v1/messages",
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: "{\"test\":true}",
                statusCode: nil
            ),
            response: LLMTraceEntry.HTTPDetails(
                url: "https://api.anthropic.com/v1/messages",
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: "{\"result\":\"ok\"}",
                statusCode: 200
            ),
            error: nil,
            duration: 0.5
        )

        let data = try HARExporter.export(entries: [entry])
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let log = json["log"] as! [String: Any]
        let entries = log["entries"] as! [[String: Any]]
        XCTAssertEqual(entries.count, 1)

        let comment = entries[0]["comment"] as? String ?? ""
        XCTAssertTrue(comment.contains("trace-1"))
        XCTAssertTrue(comment.contains("claudeCode"))
    }
}

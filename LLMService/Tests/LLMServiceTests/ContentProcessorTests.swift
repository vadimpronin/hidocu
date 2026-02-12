import XCTest
@testable import LLMService

final class ContentProcessorTests: XCTestCase {
    func testTextContent() throws {
        let result = try ContentProcessor.processContent(.text("hello"))
        if case .text(let text) = result {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("Expected text result")
        }
    }

    func testFileContentBinary() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        let result = try ContentProcessor.processContent(.fileContent(data, mimeType: "image/png", filename: "test.png"))
        if case .binary(let resultData, let mime, _) = result {
            XCTAssertEqual(resultData, data)
            XCTAssertEqual(mime, "image/png")
        } else {
            XCTFail("Expected binary result")
        }
    }
}

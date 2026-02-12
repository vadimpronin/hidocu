import XCTest
@testable import LLMService

final class LLMServiceErrorTests: XCTestCase {

    func testLocalizedDescriptionIncludesMessage() {
        let error = LLMServiceError(traceId: "t1", message: "Something went wrong")
        XCTAssertEqual(error.localizedDescription, "Something went wrong")
    }

    func testLocalizedDescriptionIncludesStatusCode() {
        let error = LLMServiceError(traceId: "t1", message: "Not Found", statusCode: 404)
        XCTAssertEqual(error.localizedDescription, "[404] Not Found")
    }

    func testLocalizedDescriptionWithAPIErrorBody() {
        let apiError = """
        {"error":{"code":500,"message":"Internal error encountered."}}
        """
        let error = LLMServiceError(traceId: "t1", message: apiError, statusCode: 500)
        XCTAssertTrue(error.localizedDescription.contains("500"))
        XCTAssertTrue(error.localizedDescription.contains("Internal error encountered."))
    }

    func testErrorDescriptionMatchesLocalizedDescription() {
        let error = LLMServiceError(traceId: "t1", message: "test", statusCode: 403)
        // LocalizedError.errorDescription feeds localizedDescription
        XCTAssertEqual(error.errorDescription, "[403] test")
    }

    func testErrorWithoutStatusCodeOmitsBrackets() {
        let error = LLMServiceError(traceId: "t1", message: "No token")
        XCTAssertFalse(error.localizedDescription.contains("["))
    }
}

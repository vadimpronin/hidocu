import XCTest
@testable import LLMService

final class PKCEGeneratorTests: XCTestCase {
    func testGeneratePKCECodes() throws {
        let codes = try PKCEGenerator.generate()

        // Verifier should be 128 chars (96 bytes * 4/3 base64)
        XCTAssertEqual(codes.codeVerifier.count, 128)

        // Verifier should be base64url (no +, /, or =)
        XCTAssertFalse(codes.codeVerifier.contains("+"))
        XCTAssertFalse(codes.codeVerifier.contains("/"))
        XCTAssertFalse(codes.codeVerifier.contains("="))

        // Challenge should be 43 chars (32 bytes SHA256 -> base64url no padding)
        XCTAssertEqual(codes.codeChallenge.count, 43)

        // Challenge should also be base64url
        XCTAssertFalse(codes.codeChallenge.contains("+"))
        XCTAssertFalse(codes.codeChallenge.contains("/"))
        XCTAssertFalse(codes.codeChallenge.contains("="))
    }

    func testPKCECodesAreUnique() throws {
        let codes1 = try PKCEGenerator.generate()
        let codes2 = try PKCEGenerator.generate()
        XCTAssertNotEqual(codes1.codeVerifier, codes2.codeVerifier)
        XCTAssertNotEqual(codes1.codeChallenge, codes2.codeChallenge)
    }
}

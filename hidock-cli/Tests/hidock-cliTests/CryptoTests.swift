import XCTest
@testable import hidock_cli

class CryptoTests: XCTestCase {
    
    func testMD5HexMatchesKnownValue() {
        // "Hello World" -> b10a8db164e0754105b7a99be72e3fe5
        let data = "Hello World".data(using: .utf8)!
        let hash = Crypto.md5Hex(data)
        
        XCTAssertEqual(hash, "b10a8db164e0754105b7a99be72e3fe5")
    }
    
    func testMD5HexMatchesEmptyString() {
        // "" -> d41d8cd98f00b204e9800998ecf8427e
        let data = Data()
        let hash = Crypto.md5Hex(data)
        
        XCTAssertEqual(hash, "d41d8cd98f00b204e9800998ecf8427e")
    }
}

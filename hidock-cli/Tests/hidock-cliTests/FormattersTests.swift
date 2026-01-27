import XCTest
@testable import hidock_cli

class FormattersTests: XCTestCase {
    
    // MARK: - Duration Formatting
    
    func testFormatDurationHandlesZero() {
        XCTAssertEqual(Formatters.formatDuration(0), "00:00:00")
    }
    
    func testFormatDurationHandlesMinutes() {
        XCTAssertEqual(Formatters.formatDuration(65), "00:01:05")
    }
    
    func testFormatDurationHandlesHours() {
        XCTAssertEqual(Formatters.formatDuration(3665), "01:01:05")
    }
    
    // MARK: - Size Formatting
    
    func testFormatSizeHandlesBytes() {
        XCTAssertEqual(Formatters.formatSize(500), "500 B")
    }
    
    func testFormatSizeHandlesKB() {
        XCTAssertEqual(Formatters.formatSize(1500), "1.5 KB")
    }
    
    func testFormatSizeHandlesMB() {
        XCTAssertEqual(Formatters.formatSize(1_500_000), "1.4 MB")
    }
    
    func testFormatSizeHandlesGB() {
        XCTAssertEqual(Formatters.formatSize(1_500_000_000), "1.4 GB")
    }
}

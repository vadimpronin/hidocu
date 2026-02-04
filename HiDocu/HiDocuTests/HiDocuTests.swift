//
//  HiDocuTests.swift
//  HiDocuTests
//
//  Unit tests for HiDocu.
//

import XCTest
@testable import HiDocu

final class HiDocuTests: XCTestCase {
    
    func testRecordingDurationFormatting() {
        // Test duration formatting extension
        XCTAssertEqual(61.formattedDuration, "1:01")
        XCTAssertEqual(3661.formattedDuration, "1:01:01")
        XCTAssertEqual(0.formattedDuration, "0:00")
    }
    
    func testRecordingStatusRawValues() {
        // Verify status raw values match expected database values
        XCTAssertEqual(RecordingStatus.new.rawValue, "new")
        XCTAssertEqual(RecordingStatus.downloaded.rawValue, "downloaded")
        XCTAssertEqual(RecordingStatus.transcribed.rawValue, "transcribed")
    }
    
    func testRecordingModeRawValues() {
        // Verify mode raw values match expected database values
        XCTAssertEqual(RecordingMode.call.rawValue, "call")
        XCTAssertEqual(RecordingMode.room.rawValue, "room")
        XCTAssertEqual(RecordingMode.whisper.rawValue, "whisper")
    }
}

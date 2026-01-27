import XCTest
@testable import JensenUSB

final class ProtocolEncoderTests: XCTestCase {
    
    func testEncodesCorrectHeader() {
        let command = Command(.queryDeviceInfo)
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data[0], 0x12)
        XCTAssertEqual(data[1], 0x34)
    }
    
    func testEncodesCommandIdBigEndian() {
        // using queryDeviceInfo which is ID 1
        let command = Command(.queryDeviceInfo)
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data[2], 0x00)
        XCTAssertEqual(data[3], 0x01)
        
        // Test a larger ID, e.g. bluetoothScan (4097 = 0x1001)
        let btCommand = Command(.bluetoothScan)
        let btData = ProtocolEncoder.encode(btCommand)
        XCTAssertEqual(btData[2], 0x10)
        XCTAssertEqual(btData[3], 0x01)
    }
    
    func testEncodesSequenceNumberBigEndian() {
        var command = Command(.queryDeviceInfo)
        command.setSequence(0x12345678)
        
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data[4], 0x12)
        XCTAssertEqual(data[5], 0x34)
        XCTAssertEqual(data[6], 0x56)
        XCTAssertEqual(data[7], 0x78)
    }
    
    func testEncodesSequenceZero() {
        var command = Command(.queryDeviceInfo)
        command.setSequence(0)
        
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data[4], 0x00)
        XCTAssertEqual(data[5], 0x00)
        XCTAssertEqual(data[6], 0x00)
        XCTAssertEqual(data[7], 0x00)
    }
    
    func testEncodesSequenceMaxValue() {
        var command = Command(.queryDeviceInfo)
        command.setSequence(0xFFFFFFFF)
        
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data[4], 0xFF)
        XCTAssertEqual(data[5], 0xFF)
        XCTAssertEqual(data[6], 0xFF)
        XCTAssertEqual(data[7], 0xFF)
    }
    
    func testEncodesEmptyBodyLength() {
        let command = Command(.queryDeviceInfo) // empty body
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data[8], 0x00) // Reserved/Padding
        XCTAssertEqual(data[9], 0x00)
        XCTAssertEqual(data[10], 0x00)
        XCTAssertEqual(data[11], 0x00)
    }
    
    func testEncodesBodyLengthBigEndian() {
        // Create dummy body of 258 bytes (0x0102)
        var body = [UInt8](repeating: 0xAA, count: 258)
        let command = Command(.transferFile, body: body)
        
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data[8], 0x00) // Reserved
        XCTAssertEqual(data[9], 0x00)
        XCTAssertEqual(data[10], 0x01)
        XCTAssertEqual(data[11], 0x02)
    }
    
    func testEncodesBodyBytes() {
        let body: [UInt8] = [0xAA, 0xBB, 0xCC]
        let command = Command(.transferFile, body: body)
        
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data.count, 12 + 3)
        XCTAssertEqual(data[12], 0xAA)
        XCTAssertEqual(data[13], 0xBB)
        XCTAssertEqual(data[14], 0xCC)
    }
    
    func testEncodesQueryDeviceInfo() {
        var command = Command(.queryDeviceInfo)
        command.setSequence(0x12345678)
        
        let data = ProtocolEncoder.encode(command)
        
        XCTAssertEqual(data.count, 12)
        XCTAssertEqual(Array(data), [
            0x12, 0x34,             // Header
            0x00, 0x01,             // ID
            0x12, 0x34, 0x56, 0x78, // Sequence
            0x00, 0x00, 0x00, 0x00  // Length
        ])
    }
}

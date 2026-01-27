import XCTest
import JensenUSB

public class TestHelpers {
    /// Create a valid response Message for a given command
    public static func makeResponse(for commandID: CommandID, sequence: UInt32, body: [UInt8]) -> Message {
        return Message(id: commandID.rawValue, sequence: sequence, body: Data(body))
    }
    
    /// Create a complete packet (header + body) for testing decoder
    public static func makePacket(commandID: UInt16, sequence: UInt32, body: [UInt8]) -> Data {
        var packet = Data()
        packet.append(0x12)
        packet.append(0x34)
        
        packet.append(UInt8((commandID >> 8) & 0xFF))
        packet.append(UInt8(commandID & 0xFF))
        
        packet.append(UInt8((sequence >> 24) & 0xFF))
        packet.append(UInt8((sequence >> 16) & 0xFF))
        packet.append(UInt8((sequence >> 8) & 0xFF))
        packet.append(UInt8(sequence & 0xFF))
        
        let length = UInt32(body.count)
        packet.append(UInt8((length >> 24) & 0xFF))
        packet.append(UInt8((length >> 16) & 0xFF))
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))
        
        packet.append(contentsOf: body)
        return packet
    }
    
    /// Create BCD time bytes for a specific date
    public static func makeBCDTime(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> [UInt8] {
        // Format: YYYYMMDDHHmmss
        let yearStr = String(format: "%04d", year)
        let monthStr = String(format: "%02d", month)
        let dayStr = String(format: "%02d", day)
        let hourStr = String(format: "%02d", hour)
        let minStr = String(format: "%02d", minute)
        let secStr = String(format: "%02d", second)
        
        // Combine to single string
        let dateStr = "\(yearStr)\(monthStr)\(dayStr)\(hourStr)\(minStr)\(secStr)"
        
        // Convert to BCD bytes
        // Each 2 chars -> 1 byte
        var result: [UInt8] = []
        let chars = Array(dateStr)
        
        for i in stride(from: 0, to: chars.count - 1, by: 2) {
            let high = UInt8(String(chars[i]))! & 0x0F
            let low = UInt8(String(chars[i + 1]))! & 0x0F
            result.append((high << 4) | low)
        }
        
        return result
    }
    public static func makeDeviceInfoBody(version: String = "1.0.0", sn: String = "SN", verNum: UInt32 = 0x01000000) -> [UInt8] {
        var body = Data()
        body.append(UInt8(version.count))
        body.append(contentsOf: version.utf8)
        
        body.append(UInt8((verNum >> 24) & 0xFF))
        body.append(UInt8((verNum >> 16) & 0xFF))
        body.append(UInt8((verNum >> 8) & 0xFF))
        body.append(UInt8(verNum & 0xFF))
        
        body.append(UInt8(sn.count))
        body.append(contentsOf: sn.utf8)
        
        return Array(body)
    }
}

extension XCTestCase {
    /// Assert Data matches expected byte array
    public func assertDataEquals(_ data: Data, _ expected: [UInt8], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(Array(data), expected, file: file, line: line)
    }
    
    /// Assert Data contains subsequence at offset
    public func assertDataContains(_ data: Data, _ subsequence: [UInt8], at offset: Int, file: StaticString = #file, line: UInt = #line) {
        let end = offset + subsequence.count
        guard data.count >= end else {
            XCTFail("Data too short explicitly to contain subsequence", file: file, line: line)
            return
        }
        let actual = Array(data[offset..<end])
        XCTAssertEqual(actual, subsequence, file: file, line: line)
    }
}

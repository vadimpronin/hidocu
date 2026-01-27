import XCTest
@testable import JensenUSB

final class ProtocolDecoderTests: XCTestCase {
    
    func testRejectsInvalidHeader() {
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertThrowsError(try ProtocolDecoder.decode(data)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.malformedHeader)
        }
    }
    
    func testAcceptsValidHeader() {
        let data = Data([
            0x12, 0x34,             // Header
            0x00, 0x01,             // ID
            0x00, 0x00, 0x00, 0x00, // Sequence
            0x00, 0x00, 0x00, 0x00  // Length
        ])
        
        XCTAssertNoThrow(try ProtocolDecoder.decode(data))
    }
    
    func testParsesCommandId() {
        let data = Data([
            0x12, 0x34,
            0x10, 0x01,             // ID = 4097 (Bluetooth Scan)
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ])
        
        guard let (message, _) = try? ProtocolDecoder.decode(data) else {
            XCTFail("Failed to decode")
            return
        }
        
        XCTAssertEqual(message.id, 4097)
    }
    
    func testParsesSequenceNumber() {
        let data = Data([
            0x12, 0x34,
            0x00, 0x01,
            0x12, 0x34, 0x56, 0x78, // Sequence
            0x00, 0x00, 0x00, 0x00
        ])
        
        guard let (message, _) = try? ProtocolDecoder.decode(data) else {
            XCTFail("Failed to decode")
            return
        }
        
        XCTAssertEqual(message.sequence, 0x12345678)
    }
    
    func testParsesBodyLength() {
        // Body length 5: 0x000005
        let data = Data([
            0x12, 0x34,
            0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x05, // Length = 5
            0x01, 0x02, 0x03, 0x04, 0x05 // Body
        ])
        
        guard let (message, consumed) = try? ProtocolDecoder.decode(data) else {
            XCTFail("Failed to decode")
            return
        }
        
        XCTAssertEqual(message.body.count, 5)
        XCTAssertEqual(consumed, 12 + 5)
    }
    
    func testParsesBodyLengthWithPadding() {
        // Body length 5, padding 2: 0x020005
        // Total length should be 12 + 5 + 2 = 19
        let data = Data([
            0x12, 0x34,
            0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x02, 0x00, 0x00, 0x05, // Length = 5, Padding = 2
            0x01, 0x02, 0x03, 0x04, 0x05, // Body
            0x00, 0x00 // Padding bytes (content doesn't matter, but must be present)
        ])
        
        guard let (message, consumed) = try? ProtocolDecoder.decode(data) else {
            XCTFail("Failed to decode")
            return
        }
        
        XCTAssertEqual(message.body.count, 5)
        XCTAssertEqual(consumed, 12 + 5 + 2)
    }
    
    func testIncompleteMessageReturnsNil() {
        // Missing last byte of body
        let data = Data([
            0x12, 0x34,
            0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x05,
            0x01, 0x02, 0x03, 0x04 // only 4 bytes
        ])
        
        XCTAssertNil(try? ProtocolDecoder.decode(data))
    }
    
    func testParsesMultipleMessages() {
        // One complete message followed by another
        var data = Data([
            // Msg 1
            0x12, 0x34,
            0x00, 0x01,
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            // Msg 2
            0x12, 0x34,
            0x00, 0x02,
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00, 0x00, 0x00
        ])
        
        let (messages, consumed) = ProtocolDecoder.decodeStream(data)
        
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].id, 1)
        XCTAssertEqual(messages[1].id, 2)
        XCTAssertEqual(consumed, 24)
    }
    
    func testParsesPartialMessageInStream() {
        // One complete message, one partial
        var data = Data([
            // Msg 1 (complete)
            0x12, 0x34,
            0x00, 0x01,
            0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            // Msg 2 (partial - header only)
            0x12, 0x34,
            0x00, 0x02
        ])
        
        let (messages, consumed) = ProtocolDecoder.decodeStream(data)
        
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(consumed, 12) // Only first message consumed
    }
    
    func testDecodesWithSlicedData() {
        // Data with non-zero startIndex (slice)
        var original = Data([0xFF, 0xFF, 0xFF])
        original.append(contentsOf: [
            0x12, 0x34,
            0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ])
        
        let slice = original.dropFirst(3)
        let subData = Data(slice)
        XCTAssertNoThrow(try ProtocolDecoder.decode(subData))
    }
}

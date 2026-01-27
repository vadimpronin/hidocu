import XCTest
@testable import JensenUSB
import JensenTestSupport

class TimeControllerTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    var timeController: TimeController!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .h1
        
        // Mock connection setup
        var body = Data()
        body.append(5) // VerLen
        body.append(contentsOf: "1.0.0".utf8)
        body.append(contentsOf: [0x00, 0x06, 0x00, 0x00]) // Version Number > 5.1.A
        body.append(2) // SNLen
        body.append(contentsOf: "H1".utf8)
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
        
        jensen = Jensen(transport: mockTransport)
        try! jensen.connect()
        
        mockTransport.clearSentCommands()
        timeController = jensen.time
    }
    
    override func tearDown() {
        jensen.disconnect()
        super.tearDown()
    }
    
    // MARK: - Get Time
    
    func testGetTimeReturnsFormattedTime() {
        // Arrange: 2025-01-27 12:34:56
        // BCD: 0x20 0x25 0x01 0x27 0x12 0x34 0x56
        let bcd: [UInt8] = [0x20, 0x25, 0x01, 0x27, 0x12, 0x34, 0x56]
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceTime, sequence: 1, body: bcd))
        
        // Act
        let time = try! timeController.get()
        
        // Assert
        XCTAssertEqual(time.timeString, "2025-01-27 12:34:56")
    }
    
    func testGetTimeHandlesZeroTime() {
        let bcd: [UInt8] = [0, 0, 0, 0, 0, 0, 0]
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceTime, sequence: 1, body: bcd))
        
        // Act
        let time = try! timeController.get()
        
        // Assert
        XCTAssertEqual(time.timeString, "unknown")
    }
    
    // MARK: - Set Time
    
    func testSetTimeEncodesSpecificDate() {
        // Arrange
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        let date = formatter.date(from: "2025-01-27 12:34:56")!
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .setDeviceTime, sequence: 1, body: []))
        
        // Act
        try! timeController.set(date)
        
        // Assert
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        
        // Verify Body: BCD of date
        let body = [UInt8](cmds[0].subdata(in: 12..<19))
        XCTAssertEqual(body, [0x20, 0x25, 0x01, 0x27, 0x12, 0x34, 0x56])
    }
}

import XCTest
@testable import JensenUSB
import JensenTestSupport

class JensenTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .h1
        jensen = Jensen(transport: mockTransport, verbose: false)
    }
    
    override func tearDown() {
        jensen.disconnect()
        super.tearDown()
    }
    
    // MARK: - Connection
    
    func testConnectOpensTransportAndGetsInfo() {
        // Arrange
        // New Format: 4 bytes version + 16 bytes serial
        var body = Data()
        body.append(contentsOf: [0, 1, 2, 3]) // VerNum 0x00010203 -> ver 1.2.3
        body.append(contentsOf: "SN1".utf8)
        body.append(Data(count: 13)) // Pad to 16 bytes
        
        let infoResponse = TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body))
        mockTransport.addResponse(infoResponse)
        
        // Act
        try! jensen.connect()
        
        // Assert
        XCTAssertTrue(jensen.isConnected)
        XCTAssertTrue(mockTransport.isConnected)
        XCTAssertEqual(jensen.versionCode, "1.2.3")
        XCTAssertEqual(jensen.serialNumber, "SN1")
    }
    
    func testConnectThrowsIfTransportFails() {
        mockTransport.shouldConnect = false
        
        XCTAssertThrowsError(try jensen.connect())
        XCTAssertFalse(jensen.isConnected)
    }
    
    func testDisconnectClosesTransport() {
        // Connect first
        var body = Data()
        body.append(contentsOf: [0, 1, 0, 0]) // 1.0.0
        body.append(contentsOf: "SN".utf8)
        body.append(Data(count: 14)) // Pad to 16 bytes
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
        try! jensen.connect()
        
        XCTAssertTrue(mockTransport.isConnected)
        
        // Act
        jensen.disconnect()
        
        // Assert
        XCTAssertFalse(mockTransport.isConnected)
    }
    
    // MARK: - Command Sending
    
    func testSendIncrementsSequence() {
        // Connect
        var body = Data()
        body.append(contentsOf: [0, 1, 0, 0])
        body.append(contentsOf: "SN".utf8)
        body.append(Data(count: 14))
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
        try! jensen.connect()
        
        // Mock responses for 2 commands
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceTime, sequence: 2, body: [])) // seq 2 because 1 used by connect
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceTime, sequence: 3, body: []))
        
        // Act
        var cmd1 = Command(.queryDeviceTime)
        _ = try! jensen.send(&cmd1)
        
        var cmd2 = Command(.queryDeviceTime)
        _ = try! jensen.send(&cmd2)
        
        // Assert
        XCTAssertEqual(cmd1.sequence, 2)
        XCTAssertEqual(cmd2.sequence, 3)
        // Check internal jensen sequence
        // Note: internal sequence is unaccessible directly unless internal, tests are in same module if @testable
        // or we check sequence of sent commands in mock
        let sent = mockTransport.getAllSentCommands()
        // 0: connect (seq 1), 1: cmd1 (seq 2), 2: cmd2 (seq 3)
        XCTAssertEqual(sent[1][7], 2) // Sequence LSB
        XCTAssertEqual(sent[2][7], 3)
    }
    
    func testSendWaitsForMatchingResponse() {
         // Connect
         var body = Data()
         body.append(contentsOf: [0, 1, 0, 0])
         body.append(contentsOf: "SN".utf8)
         body.append(Data(count: 14))
         mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
         try! jensen.connect()
         
         // Add mismatched response (wrong ID) followed by correct one
         // Mismatched: ID 999 (invalid), seq 2
         mockTransport.addResponse(TestHelpers.makeResponse(for: .invalid, sequence: 2, body: []))
         
         // Correct: ID 2 (queryDeviceTime), seq 2
         mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceTime, sequence: 2, body: []))
         
         // Act
         var cmd = Command(.queryDeviceTime)
         _ = try! jensen.send(&cmd)
         
         // Should succeed by ignoring the first mismatched response
    }
    
    func testSendTimesOut() {
        // Connect
         var body = Data()
         body.append(contentsOf: [0, 1, 0, 0])
         body.append(contentsOf: "SN".utf8)
         body.append(Data(count: 14))
         mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
         try! jensen.connect()
         
         // No response added
         
         // Act & Assert
         var cmd = Command(.queryDeviceTime)
         XCTAssertThrowsError(try jensen.send(&cmd, timeout: 0.1)) { error in
             XCTAssertEqual(error as? JensenError, JensenError.commandTimeout)
         }
    }
}

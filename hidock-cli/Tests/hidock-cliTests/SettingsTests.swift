import XCTest
import ArgumentParser
import JensenUSB
import JensenTestSupport
@testable import hidock_cli

class SettingsTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .h1
        jensen = Jensen(transport: mockTransport)
        
        JensenFactory.make = { [unowned self] verbose in
            if self.jensen.verbose != verbose {
                self.jensen.verbose = verbose
            }
            return self.jensen
        }
    }
    
    override func tearDown() {
        JensenFactory.make = { verbose in
            return Jensen(verbose: verbose)
        }
        jensen.disconnect()
        super.tearDown()
    }
    
    // Helper to mock connection with high version
    private func mockConnection() {
        let body = TestHelpers.makeDeviceInfoBody(verNum: 0x10000000)
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: body))
    }
    
    func testSettingsGet() throws {
        mockConnection()
        
        var body = [UInt8](repeating: 0, count: 16)
        body[3] = 1  // Record ON
        body[7] = 2  // Play OFF
        body[11] = 1 // Notif ON
        body[15] = 2 // BT Tone ON (inverted)
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .getSettings, sequence: 2, body: body))
        
        let cmd = try SettingsGet.parse([])
        try cmd.run()
        
        XCTAssertEqual(mockTransport.sentCommands.count, 2)
    }
    
    func testSettingsSetAutoRecord() throws {
        mockConnection()
        mockTransport.addResponse(TestHelpers.makeResponse(for: .setSettings, sequence: 2, body: []))
        
        let cmd = try SettingsSetAutoRecord.parse(["on"])
        try cmd.run()
        
        XCTAssertEqual(mockTransport.sentCommands.count, 2)
        let sent = mockTransport.sentCommands[1]
        // Header(12) + Offset 3 -> 15
        XCTAssertEqual(sent[15], 1) // ON
    }
    
    func testSettingsSetBTTone() throws {
        mockConnection()
        mockTransport.addResponse(TestHelpers.makeResponse(for: .setSettings, sequence: 2, body: []))
        
        let cmd = try SettingsSetBTTone.parse(["on"])
        try cmd.run()
        
        XCTAssertEqual(mockTransport.sentCommands.count, 2)
        let sent = mockTransport.sentCommands[1]
        // Header(12) + Offset 15 -> 27
        XCTAssertEqual(sent[27], 2) // ON is 2 for BT Tone
    }
}

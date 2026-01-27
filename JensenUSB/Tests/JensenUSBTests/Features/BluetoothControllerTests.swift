import XCTest
@testable import JensenUSB
import JensenTestSupport

class BluetoothControllerTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    var bluetooth: BluetoothController!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .p1 // Use P1 for bluetooth tests
        jensen = Jensen(transport: mockTransport, verbose: false)
        
        // Mock connection (P1)
        var body = Data()
        body.append(0) // VerLen (empty)
        body.append(contentsOf: [0x00, 0x01, 0x00, 0x00]) // Ver
        body.append(0) // SNLen
        
        // Jensen.connect expects at least 12 bytes if ver len is 0? 
        // Logic: guard response.body.count >= 12 
        // So we need to pad the body
        // P1 might return differnt info, but let's just make it parsable
        // 1 + 0 + 4 + 1 + 0 = 6 bytes? No, line 143: guard count >= 12
        // So we need padding
        while body.count < 12 { body.append(0) }
        
        let infoResponse = TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body))
        mockTransport.addResponse(infoResponse)
        
        try! jensen.connect()
        mockTransport.clearSentCommands()
        
        bluetooth = jensen.bluetooth
    }
    
    func testGetStatusReturnsDisconnected() {
        // Status ID 4099 (0x1003)
        // Body: [1] = disconnected
        mockTransport.addResponse(TestHelpers.makeResponse(for: .bluetoothStatus, sequence: 1, body: [1]))
        
        let status = try! bluetooth.getStatus()
        XCTAssertEqual(status?["status"] as? String, "disconnected")
    }
    
    func testGetStatusReturnsConnectedWithDetails() {
        // Body: 
        // 0: Status (any > 3 usually, or logic falls through) -> let's say 4
        // 1-2: Name Length (e.g. 4) -> 0x00 0x04
        // 3-6: Name "Test" -> 0x54 0x65 0x73 0x74
        // 7-12: MAC (6 bytes) -> AA BB CC DD EE FF
        // 13: A2DP (1/0)
        // 14: HFP
        // 15: AVRCP
        // 16: Batt (0-255)
        
        var body = Data()
        body.append(4) // Status connected
        body.append(contentsOf: [0x00, 0x04]) // Name len
        body.append(contentsOf: "Test".utf8)
        body.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]) // MAC
        body.append(1) // A2DP
        body.append(0) // HFP
        body.append(1) // AVRCP
        body.append(204) // Batt (80% -> 204/255 approx 0.8)
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .bluetoothStatus, sequence: 1, body: [UInt8](body)))
        
        let status = try! bluetooth.getStatus()
        XCTAssertEqual(status?["status"] as? String, "connected")
        XCTAssertEqual(status?["name"] as? String, "Test")
        XCTAssertEqual(status?["mac"] as? String, "AA-BB-CC-DD-EE-FF")
        XCTAssertEqual(status?["a2dp"] as? Bool, true)
        XCTAssertEqual(status?["battery"] as? Int, 80)
    }
    
    func testStartScanSendsCorrectCommand() {
        mockTransport.addResponse(TestHelpers.makeResponse(for: .btScan, sequence: 1, body: []))
        
        try! bluetooth.startScan(duration: 15)
        
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        // Body: [1, 15]
        let bodyOffset = 12
        XCTAssertEqual(cmds[0][bodyOffset], 1)
        XCTAssertEqual(cmds[0][bodyOffset+1], 15)
    }
    
    func testConnectSendsCorrectCommand() {
        mockTransport.addResponse(TestHelpers.makeResponse(for: .bluetoothCmd, sequence: 1, body: []))
        
        try! bluetooth.connect(mac: "11-22-33-44-55-66")
        
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        // Body: [0, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66]
        let bodyOffset = 12
        XCTAssertEqual(cmds[0][bodyOffset], 0) // Subcommand 0
        XCTAssertEqual(cmds[0][bodyOffset+1], 0x11)
        XCTAssertEqual(cmds[0][bodyOffset+6], 0x66)
    }
}

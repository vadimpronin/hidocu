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
        
        // Mock connection (P1)
        var body = Data()
        body.append(0) // VerLen (empty)
        body.append(contentsOf: [0x00, 0x01, 0x00, 0x00]) // Ver
        body.append(0) // SNLen
        while body.count < 12 { body.append(0) }
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
        
        jensen = Jensen(transport: mockTransport)
        try! jensen.connect()
        
        mockTransport.clearSentCommands()
        bluetooth = jensen.bluetooth
    }
    
    override func tearDown() {
        jensen.disconnect()
        super.tearDown()
    }
    
    func testGetStatusReturnsDisconnected() {
        // Body: [1] = disconnected
        mockTransport.addResponse(TestHelpers.makeResponse(for: .bluetoothStatus, sequence: 1, body: [1]))
        
        let status = try! bluetooth.getStatus()
        XCTAssertEqual(status?["status"] as? String, "disconnected")
    }
    
    func testGetStatusReturnsConnectedWithDetails() {
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
        
        try! bluetooth.startScan(duration: 1) // Short duration
        
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        // Body: [1, 15]
        let bodyOffset = 12
        XCTAssertEqual(cmds[0][bodyOffset], 1)
        XCTAssertEqual(cmds[0][bodyOffset+1], 1)
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

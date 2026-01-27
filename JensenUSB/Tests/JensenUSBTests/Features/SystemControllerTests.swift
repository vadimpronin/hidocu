import XCTest
@testable import JensenUSB
import JensenTestSupport

class SystemControllerTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    var systemController: SystemController!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .p1
        
        // Mock connection setup
        var body = Data(repeating: 0, count: 12)
        body[0] = 1
        body[1] = 0x31 // "1"
        body[2] = 0x00; body[3] = 0x06; body[4] = 0x00; body[5] = 0x00
        body[6] = 0
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
        
        jensen = Jensen(transport: mockTransport)
        try! jensen.connect()
        
        mockTransport.clearSentCommands()
        systemController = jensen.system
    }
    
    override func tearDown() {
        jensen.disconnect()
        super.tearDown()
    }
    
    func testGetBatteryStatus() {
        // Body: [State(1=charging), % (50), V, V, V, V]
        var body: [UInt8] = [1, 50, 0, 0, 0, 0]
        mockTransport.addResponse(TestHelpers.makeResponse(for: .getBatteryStatus, sequence: 1, body: body))
        
        let status = try! systemController.getBatteryStatus()
        
        XCTAssertEqual(status.percentage, 50)
        XCTAssertEqual(status.status, "charging")
    }
    
    func testGetCardInfo() {
        // Body (12 bytes): [Free(4) | Capacity(4) | Status(4)]
        var body: [UInt8] = []
        body.append(contentsOf: [0, 0, 0, 90])  // Free MB
        body.append(contentsOf: [0, 0, 0, 100]) // Capacity MB
        body.append(contentsOf: [0, 0, 0, 0])   // Status
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .readCardInfo, sequence: 1, body: body))
        
        let info = try! systemController.getCardInfo()
        
        let mb: UInt64 = 1024 * 1024
        XCTAssertEqual(info.status, "ok")
        XCTAssertEqual(info.capacity, 100 * mb)
        XCTAssertEqual(info.used, 10 * mb)
    }
    
    func testRequestFirmwareUpgradeEncodesCorrectly() {
        // 0x00 = Accepted
        mockTransport.addResponse(TestHelpers.makeResponse(for: .requestFirmwareUpgrade, sequence: 1, body: [0x00]))
        
        let ver: UInt32 = 0x01020304
        let size: UInt32 = 1000
        
        let result = try! systemController.requestFirmwareUpgrade(versionNumber: ver, fileSize: size)
        
        XCTAssertEqual(result, .accepted)
        
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        
        // Body (12 offset)
        XCTAssertEqual(cmds[0][12], 0x01)
        XCTAssertEqual(cmds[0][15], 0x04)
        XCTAssertEqual(cmds[0][16], 0x00)
        XCTAssertEqual(cmds[0][19], 0xE8)
    }
}

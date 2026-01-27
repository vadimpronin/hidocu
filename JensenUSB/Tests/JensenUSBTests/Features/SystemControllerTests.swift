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
        mockTransport.mockModel = .p1 // Supports battery
        jensen = Jensen(transport: mockTransport, verbose: false)
        
        // Mock connection
        var body = Data(repeating: 0, count: 12)
        // Version len 1, "1", Version 6.0, SN len 0
        body[0] = 1
        body[1] = 0x31 // "1"
        body[2] = 0x00; body[3] = 0x06; body[4] = 0x00; body[5] = 0x00
        body[6] = 0
        
        let infoResponse = TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body))
        mockTransport.addResponse(infoResponse)
        
        try! jensen.connect()
        mockTransport.clearSentCommands()
        
        systemController = jensen.system
    }
    
    func testGetBatteryStatus() {
        // Body: [State(1=charging), % (50), V, V, V, V]
        var body: [UInt8] = [1, 50, 0, 0, 0, 0]
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .getBatteryStatus, sequence: 1, body: body))
        
        let status = try! systemController.getBatteryStatus()
        
        XCTAssertEqual(status.status, "charging")
        XCTAssertEqual(status.percentage, 50)
    }
    
    func testGetCardInfo() {
        // Body: [Status(0=ok), Cap,Cap,Cap,Cap, Used,Used,Used,Used]
        // Cap = 100 KB (0x64), Used = 50 KB (0x32)
        var body: [UInt8] = [0]
        body.append(contentsOf: [0, 0, 0, 100])
        body.append(contentsOf: [0, 0, 0, 50])
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .readCardInfo, sequence: 1, body: body))
        
        let info = try! systemController.getCardInfo()
        
        XCTAssertEqual(info.status, "ok")
        XCTAssertEqual(info.capacity, 100 * 1024)
        XCTAssertEqual(info.used, 50 * 1024)
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
        // Ver: 0x01 0x02 0x03 0x04
        XCTAssertEqual(cmds[0][12], 0x01)
        XCTAssertEqual(cmds[0][15], 0x04)
        // Size: 0x00 0x00 0x03 0xE8 (1000)
        XCTAssertEqual(cmds[0][16], 0x00)
        XCTAssertEqual(cmds[0][19], 0xE8)
    }
}

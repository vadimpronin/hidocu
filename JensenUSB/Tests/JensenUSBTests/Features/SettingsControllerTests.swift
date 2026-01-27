import XCTest
@testable import JensenUSB
import JensenTestSupport

class SettingsControllerTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    var settingsController: SettingsController!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .h1
        
        // Mock connection response
        var body = Data()
        body.append(5)
        body.append(contentsOf: "1.0.0".utf8)
        body.append(contentsOf: [0x00, 0x06, 0x00, 0x00])
        body.append(2)
        body.append(contentsOf: "H1".utf8)
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
        
        jensen = Jensen(transport: mockTransport)
        try! jensen.connect()
        
        mockTransport.clearSentCommands()
        settingsController = jensen.settings
    }
    
    override func tearDown() {
        jensen.disconnect()
        super.tearDown()
    }
    
    func testGetSettingsReturnsAllSettings() {
        // Arrange
        var body = [UInt8](repeating: 0, count: 16)
        body[3] = 1  // Record ON
        body[7] = 2  // Play OFF
        body[11] = 1 // Notif ON
        body[15] = 2 // BT Tone ON (inverted 2=ON)
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .getSettings, sequence: 1, body: body))
        
        // Act
        let settings = try! settingsController.get()
        
        // Assert
        XCTAssertTrue(settings.autoRecord)
        XCTAssertFalse(settings.autoPlay)
        XCTAssertTrue(settings.notification)
        XCTAssertTrue(settings.bluetoothTone)
    }
    
    func testSetBluetoothToneOnSendsCorrectValue() {
        // ON -> sends 2 (inverted logic)
        mockTransport.addResponse(TestHelpers.makeResponse(for: .setSettings, sequence: 1, body: []))
        
        try! settingsController.setBluetoothTone(true)
        
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        XCTAssertEqual(cmds[0][12+15], 2)
    }
    
    func testSetBluetoothToneOffSendsCorrectValue() {
        // OFF -> sends 1 (inverted logic)
        mockTransport.addResponse(TestHelpers.makeResponse(for: .setSettings, sequence: 1, body: []))
        
        try! settingsController.setBluetoothTone(false)
        
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        XCTAssertEqual(cmds[0][12+15], 1)
    }
    
    func testSetAutoRecordOn() {
        // ON -> sends 1
        mockTransport.addResponse(TestHelpers.makeResponse(for: .setSettings, sequence: 1, body: []))
        
        try! settingsController.setAutoRecord(true)
        
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds[0][15], 1)
    }
}

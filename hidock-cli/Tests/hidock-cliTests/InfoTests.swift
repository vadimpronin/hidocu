import XCTest
import ArgumentParser
import JensenUSB
import JensenTestSupport
@testable import hidock_cli

class InfoTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .h1
        
        // Mock connection interaction
        // Response 1 (Connect)
        var body = Data()
        body.append(contentsOf: [1, 1, 0, 0]) // Version 1.0.0
        body.append(contentsOf: "SN".utf8)
        body.append(Data(count: 14)) // Padding to 16 bytes
        
        // Response 2 (Explicit getDeviceInfo)
        let infoResp = TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body))
        mockTransport.addResponse(infoResp)
        mockTransport.addResponse(infoResp) // Second one for the command itself
        
        jensen = Jensen(transport: mockTransport)
        
        // Inject factory
        JensenFactory.make = { [unowned self] verbose in
            if self.jensen.verbose != verbose {
                self.jensen.verbose = verbose
            }
            return self.jensen
        }
    }
    
    override func tearDown() {
        // Reset factory
        JensenFactory.make = { verbose in Jensen(verbose: verbose) }
        jensen.disconnect()
        super.tearDown()
    }
    
    func testInfoCommandRunsSuccessfully() throws {
        let info = try Info.parse([])
        
        XCTAssertNoThrow(try info.run())
        
        let cmds = mockTransport.getAllSentCommands()
        // 1. connect loop (getDeviceInfo)
        // 2. getDeviceInfo logic
        XCTAssertTrue(cmds.count >= 2)
        XCTAssertEqual(cmds[0][2], 0x00)
        XCTAssertEqual(cmds[0][3], 0x01) // Query Device Info
        XCTAssertEqual(cmds[1][2], 0x00)
        XCTAssertEqual(cmds[1][3], 0x01) // Query Device Info
    }
}

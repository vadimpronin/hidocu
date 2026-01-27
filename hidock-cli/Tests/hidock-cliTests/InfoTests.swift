import XCTest
import ArgumentParser
import JensenUSB
import JensenTestSupport
@testable import hidock_cli

class InfoTests: XCTestCase {
    var mockTransport: MockTransport!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        
        // Mock connection interaction
        // 1. connect() -> getDeviceInfo()
        // 2. run() -> getDeviceInfo() explicitly
        // So we need response for connect (kept by jensen) AND response for getDeviceInfo calls
        
        // However, Jensen implementation caches deviceInfo after connect.
        // Let's see Info.swift: 
        // try jensen.connect() -> fetches info
        // try jensen.getDeviceInfo() -> re-fetches info using legacy call?
        // Jensen.swift: func getDeviceInfo() sends queryDeviceInfo again.
        
        // So we need TWO responses for queryDeviceInfo.
        
        // Response 1 (Connect)
        var body = Data()
        body.append(5); body.append(contentsOf: "1.0.0".utf8)
        body.append(contentsOf: [0,0,0,0]); body.append(2); body.append(contentsOf: "SN".utf8)
        
        // Response 2 (Explicit getDeviceInfo)
        // Same body
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body)))
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 2, body: [UInt8](body)))
        
        // Inject factory
        JensenFactory.make = { verbose in
            let jensen = Jensen(transport: self.mockTransport, verbose: verbose)
            return jensen
        }
    }
    
    override func tearDown() {
        // Reset factory
        JensenFactory.make = { verbose in Jensen(verbose: verbose) }
        super.tearDown()
    }
    
    func testInfoCommandRunsSuccessfully() {
        var info = Info()
        info.verbose = false
        
        XCTAssertNoThrow(try info.run())
        
        let cmds = mockTransport.getAllSentCommands()
        // 1. connect loop (getDeviceInfo)
        // 2. getDeviceInfo logic
        // Verify commands sent
        XCTAssertTrue(cmds.count >= 2)
        XCTAssertEqual(cmds[0][2], 0x00)
        XCTAssertEqual(cmds[0][3], 0x01) // Query Device Info
        XCTAssertEqual(cmds[1][2], 0x00)
        XCTAssertEqual(cmds[1][3], 0x01) // Query Device Info
    }
}

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
        // New Format: Fixed structure [4 bytes Version] [16 bytes Serial]
        // Version 1.0.0 -> 0x01000000 (bytes 0,1,2,3).
        // 1.0.0 string is formed from bytes 1,2,3 -> "0.0.0" if they are 0.
        // Wait, jensen.js logic:
        // vn = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        // vc = b1 . b2 . b3
        // So for "1.0.0", we need b1='1', b2='0', b3='0' -> [?, 49, 48, 48]
        // Let's use 1.0.0 as bytes: [1, 1, 0, 0] -> vn=0x01010000, vc="1.0.0".
        // Wait, jensen.js pushes String(b). So if byte is 1 -> "1".
        // So [1, 1, 0, 0] -> 1.0.0
        
        var body = Data()
        body.append(contentsOf: [1, 1, 0, 0]) // Version 1.0.0
        
        // Serial Number "SN"
        body.append(contentsOf: "SN".utf8)
        body.append(Data(count: 14)) // Padding to 16 bytes
        
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

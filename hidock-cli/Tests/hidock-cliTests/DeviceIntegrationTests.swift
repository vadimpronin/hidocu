import XCTest
import JensenUSB
import JensenTestSupport
@testable import hidock_cli

class DeviceIntegrationTests: XCTestCase {
    var jensen: Jensen!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Skip if not in REAL mode
        try XCTSkipIf(ProcessInfo.processInfo.environment["TEST_MODE"] != "REAL", "Skipping device tests in mock mode")
        
        // Setup real transport with protection
        let transport = SafeTransport(wrapping: USBTransport())
        jensen = Jensen(transport: transport)
        
        try jensen.connect()
        
        // Inject factory for CLI commands
        JensenFactory.make = { [unowned self] _ in
            return self.jensen
        }
    }
    
    override func tearDown() {
        // Reset factory
        JensenFactory.make = { verbose in Jensen(verbose: verbose) }
        if let jensen = jensen {
            jensen.disconnect()
        }
        super.tearDown()
    }
    
    func testInfoCommand() throws {
        let info = try Info.parse([])
        XCTAssertNoThrow(try info.run())
    }
    
    func testListCommand() throws {
        let list = try List.parse([])
        XCTAssertNoThrow(try list.run())
    }
    
    func testSettingsGetCommand() throws {
        let settings = try SettingsGet.parse([])
        XCTAssertNoThrow(try settings.run())
    }
}

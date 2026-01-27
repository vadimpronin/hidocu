import XCTest
import JensenUSB
import JensenTestSupport

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
    }
    
    override func tearDown() {
        if let jensen = jensen {
            jensen.disconnect()
        }
        super.tearDown()
    }
    
    // MARK: - Integration Tests
    
    func testDeviceInfo() {
        XCTAssertNotNil(jensen.versionCode)
        XCTAssertNotNil(jensen.serialNumber)
        print("Device Version: \(jensen.versionCode ?? "unknown")")
        print("Device SN: \(jensen.serialNumber ?? "unknown")")
    }
    
    func testFileListing() throws {
        let count = try jensen.file.count()
        print("File Count: \(count.count)")
        
        let files = try jensen.file.list()
        XCTAssertEqual(files.count, count.count)
        
        if let first = files.first {
            print("First File: \(first.name), Size: \(first.length)")
        }
    }
    
    func testSystemInfo() throws {
        let battery = try jensen.system.getBatteryStatus()
        print("Battery Level: \(battery.percentage)%")
        XCTAssertTrue(battery.percentage >= 0 && battery.percentage <= 100)
        
        let card = try jensen.system.getCardInfo()
        print("Card Status: \(card.status), Used: \(card.used / 1024 / 1024) MB, Total: \(card.capacity / 1024 / 1024) MB")
    }
    
    func testTime() throws {
        let time = try jensen.time.get()
        XCTAssertNotEqual(time.timeString, "unknown")
        print("Device Time: \(time.timeString)")
    }
    
    func testBluetoothStatus() throws {
        let status = try jensen.bluetooth.getStatus()
        XCTAssertNotNil(status?["status"])
        print("Bluetooth Status: \(status?["status"] ?? "unknown")")
    }
}

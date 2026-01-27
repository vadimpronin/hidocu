import XCTest
import ArgumentParser
import JensenUSB
import JensenTestSupport
@testable import hidock_cli

class ListTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .h1
        jensen = Jensen(transport: mockTransport)
        
        // Inject our transport factory
        JensenFactory.make = { [unowned self] verbose in
            if self.jensen.verbose != verbose {
                self.jensen.verbose = verbose
            }
            return self.jensen
        }
    }
    
    override func tearDown() {
        // Reset factory to default
        JensenFactory.make = { verbose in
            return Jensen(verbose: verbose)
        }
        jensen.disconnect()
        super.tearDown()
    }
    
    func testListCommandPrintsFiles() throws {
        // 1. Connection (getDeviceInfo)
        // Use high version to skip count check for simplicity
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: TestHelpers.makeDeviceInfoBody(verNum: 0x10000000)))
        
        // 2. List Files (queryFileList)
        var fileListBody = Data()
        // Entry 1
        var entry1 = Data([1]) // Version
        let name = "test.wav"
        let nameData = name.data(using: .utf8)!
        let nameLen = UInt32(nameData.count)
        // Name len is 3 bytes in struct
        entry1.append(Data([UInt8((nameLen >> 16) & 0xFF), UInt8((nameLen >> 8) & 0xFF), UInt8(nameLen & 0xFF)]))
        entry1.append(nameData)
        
        let size: UInt32 = 1024
        entry1.append(withUnsafeBytes(of: size.bigEndian) { Data($0) })
        entry1.append(Data(count: 6)) // Reserved
        entry1.append(Data(count: 16)) // Signature
        
        fileListBody.append(entry1)
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryFileList, sequence: 2, body: Array(fileListBody)))
        
        // Execute
        let list = try List.parse(["--verbose"])
        try list.run()
        
        // Verification
        XCTAssertEqual(mockTransport.sentCommands.count, 2)
        XCTAssertEqual(Array(mockTransport.sentCommands[1][2...3]), [0x00, 0x04])
    }
    
    func testListCommandHandlesNoFiles() throws {
        // 1. Connection (getDeviceInfo) - version high
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: TestHelpers.makeDeviceInfoBody(verNum: 0x10000000)))
        
        // 2. List Files - Empty body
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryFileList, sequence: 2, body: []))
        
        let list = try List.parse([])
        try list.run()
        
        XCTAssertEqual(mockTransport.sentCommands.count, 2)
    }
}

import XCTest
import ArgumentParser
import JensenUSB
import JensenTestSupport
@testable import hidock_cli

class ListTests: XCTestCase {
    var mockTransport: MockTransport!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        // Inject our mock transport factory
        JensenFactory.make = { verbose in
            return Jensen(transport: self.mockTransport, verbose: verbose)
        }
    }
    
    override func tearDown() {
        // Reset factory to default (optional, but good practice)
        JensenFactory.make = { verbose in
            return Jensen(verbose: verbose)
        }
        super.tearDown()
    }
    
    func testListCommandPrintsFiles() throws {
        // 1. Connection (getDeviceInfo)
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: TestHelpers.makeDeviceInfoBody()))
        
        // 2. List Files (queryFileList)
        // We need to construct a valid file list response body
        // File 1: "20230101-120000.wav", size 1000
        // Minimal file entry structure: [Version(1), NameLen(3), Name(N bytes), Size(4), Reserved(6), Sig(16)]
        
        var fileListBody = Data()
        // Total count header (optional/version dependent, let's omit for simplicity or include if needed)
        // FileController checks version. If version <= 0x0005001A it checks count first.
        // Mock device info returns version number 0. So it WILL check count.
        
        // Wait, makeDeviceInfoBody returns version 1.0.0 (0x01000000 > 0x0005001A)?
        // TestHelpers.makeDeviceInfoBody probably returns 0 if valid.
        // Let's assume high version to skip count check for simplicity.
        // Device info body: Length(1), VerStr(N), VerNum(4), SNLen(1), SN(M).
        // Let's make sure VerNum is high.
        
        // Reset queue to use custom device info
        mockTransport.responseQueue.removeAll()
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: TestHelpers.makeDeviceInfoBody(verNum: 0x10000000)))
        
        // File List response
        // Entry 1
        var entry1 = Data([1]) // Version
        let name = "test.wav"
        let nameData = name.data(using: .utf8)!
        let nameLen = UInt32(nameData.count)
        // Name len is 3 bytes in struct?
        // Code: Int(bodyData[offset]) << 16 | Int(bodyData[offset + 1]) << 8 | Int(bodyData[offset + 2])
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

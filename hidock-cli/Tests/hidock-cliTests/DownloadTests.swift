import XCTest
import ArgumentParser
import JensenUSB
import JensenTestSupport
@testable import hidock_cli

class DownloadTests: XCTestCase {
    var mockTransport: MockTransport!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        JensenFactory.make = { verbose in
            return Jensen(transport: self.mockTransport, verbose: verbose)
        }
        
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        JensenFactory.make = { verbose in
            return Jensen(verbose: verbose)
        }
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testDownloadSingleFile() throws {
        // 1. Connection (High Ver)
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: TestHelpers.makeDeviceInfoBody(verNum: 0x10000000)))
        
        // 2. List Files (returns "test.wav", size 12)
        let fileSize: UInt32 = 12
        var entry1 = Data([1]) // Version
        let name = "test.wav"
        let nameData = name.data(using: .utf8)!
        let nameLen = UInt32(nameData.count)
        entry1.append(Data([UInt8((nameLen >> 16) & 0xFF), UInt8((nameLen >> 8) & 0xFF), UInt8(nameLen & 0xFF)]))
        entry1.append(nameData)
        entry1.append(withUnsafeBytes(of: fileSize.bigEndian) { Data($0) })
        entry1.append(Data(count: 6)) // Reserved
        entry1.append(Data(count: 16)) // Signature
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryFileList, sequence: 2, body: Array(entry1)))
        
        // 3. Download File (transferFile)
        // Response is just body chunks. But encapsulated in messages.
        // FileController expects messages with body.
        let fileContent = "Hello World!".data(using: .utf8)!
        mockTransport.addResponse(TestHelpers.makeResponse(for: .transferFile, sequence: 3, body: Array(fileContent)))
        
        let cmd = try Download.parse([ "test.wav", "--output", tempDir.path ])
        try cmd.run()
        
        let outputFile = tempDir.appendingPathComponent("test.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
        let content = try Data(contentsOf: outputFile)
        XCTAssertEqual(content, fileContent)
        
        XCTAssertEqual(mockTransport.sentCommands.count, 3) // Info, List, Transfer
    }
    
    func testDownloadAllFiles() throws {
        // 1. Connection
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: TestHelpers.makeDeviceInfoBody(verNum: 0x10000000)))
        
        // 2. List Files - 2 files
        var listBody = Data()
        // entry 1: "f1.wav"
        listBody.append(makeEntry(name: "f1.wav", size: 5))
        // entry 2: "f2.wav"
        listBody.append(makeEntry(name: "f2.wav", size: 5))
        
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryFileList, sequence: 2, body: Array(listBody)))
        
        // 3. Download f1
        mockTransport.addResponse(TestHelpers.makeResponse(for: .transferFile, sequence: 3, body: Array("Hello".data(using: .utf8)!)))
        
        // 4. Download f2
        mockTransport.addResponse(TestHelpers.makeResponse(for: .transferFile, sequence: 4, body: Array("World".data(using: .utf8)!)))
        
        let cmd = try Download.parse([ "--all", "--output", tempDir.path ])
        try cmd.run()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("f1.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("f2.wav").path))
        XCTAssertEqual(mockTransport.sentCommands.count, 4)
    }
    
    private func makeEntry(name: String, size: UInt32) -> Data {
        var entry = Data([1])
        let nameData = name.data(using: .utf8)!
        let nameLen = UInt32(nameData.count)
         entry.append(Data([UInt8((nameLen >> 16) & 0xFF), UInt8((nameLen >> 8) & 0xFF), UInt8(nameLen & 0xFF)]))
        entry.append(nameData)
        entry.append(withUnsafeBytes(of: size.bigEndian) { Data($0) })
        entry.append(Data(count: 6))
        entry.append(Data(count: 16))
        return entry
    }
}

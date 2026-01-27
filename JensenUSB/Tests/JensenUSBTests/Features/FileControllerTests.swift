import XCTest
@testable import JensenUSB
import JensenTestSupport

class FileControllerTests: XCTestCase {
    var mockTransport: MockTransport!
    var jensen: Jensen!
    var fileController: FileController!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        mockTransport.mockModel = .h1
        // We need to initialize Jensen with the mock transport
        // Assuming Jensen has an init accepting transport or a way to set it
        // If not, we might need to modify Jensen to accept transport injection
        // Based on previous files, Jensen init probably accepts transport.
        // Let's assume: init(transport: JensenTransport, verbose: Bool = false)
        jensen = Jensen(transport: mockTransport, verbose: false)
        
        // Add response for initial connection (getDeviceInfo)
        // Header + ID + Seq + Length + Body
        // Body: VerLen(1) + VerStr + VerNum(4) + SNLen(1) + SN
        // Minimum body for parsing: 1 + "1.0.0".count + 4 + 1 + "SN".count
        // Ver: "1.0.0" -> 5 bytes. 
        // SN: "H1" -> 2 bytes.
        // Body bytes: 0x05, 0x31, 0x2E, 0x30, 0x2E, 0x30, 
        // 0x00, 0x01, 0x00, 0x00 (Version 0x00010000),
        // 0x02, 0x48, 0x31 (SN "H1")
        
        var body = Data()
        body.append(5) // VerLen
        body.append(contentsOf: "1.0.0".utf8)
        body.append(contentsOf: [0x00, 0x06, 0x00, 0x00]) // Version Number 6.0.0
        body.append(2) // SNLen
        body.append(contentsOf: "H1".utf8)
        
        let infoResponse = TestHelpers.makeResponse(for: .queryDeviceInfo, sequence: 1, body: [UInt8](body))
        mockTransport.addResponse(infoResponse)
        
        try! jensen.connect() // Should succeed with mock
        
        // Clear queue and sent commands to have clean state for test
        mockTransport.clearSentCommands()
        fileController = jensen.file
    }
    
    override func tearDown() {
        jensen.disconnect()
        super.tearDown()
    }
    
    // MARK: - File Count Tests
    
    func testGetFileCountReturnsCorrectCount() {
        // Arrange
        // Response body: 4 bytes big-endian count
        let count: UInt32 = 42
        let body = [
            UInt8((count >> 24) & 0xFF),
            UInt8((count >> 16) & 0xFF),
            UInt8((count >> 8) & 0xFF),
            UInt8(count & 0xFF)
        ]
        
        let response = TestHelpers.makeResponse(for: .queryFileCount, sequence: 1, body: body)
        mockTransport.addResponse(response)
        
        // Act
        let result = try! fileController.count()
        
        // Assert
        XCTAssertEqual(result.count, Int(count))
        
        // Verify command
        let sentCommands = mockTransport.getAllSentCommands()
        XCTAssertEqual(sentCommands.count, 1)
        // Check command ID (0x0006 for queryFileCount)
        XCTAssertEqual(sentCommands[0][2], 0x00)
        XCTAssertEqual(sentCommands[0][3], 0x06)
    }
    
    func testGetFileCountHandlesZeroFiles() {
        let body: [UInt8] = [0, 0, 0, 0]
        mockTransport.addResponse(TestHelpers.makeResponse(for: .queryFileCount, sequence: 1, body: body))
        
        let result = try! fileController.count()
        XCTAssertEqual(result.count, 0)
    }
    
    // MARK: - File List Tests
    
    func testListFilesParsesSingleFile() {
        // Arrange
        // Construct a file list response
        // Header (0xFF 0xFF) + Count (4 bytes)
        var bodyData = Data([0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01])
        
        let fileName = "20250127REC001.wav"
        let fileSize: UInt32 = 65536
        
        // File 1
        bodyData.append(0x01) // Version
        
        // Name length (3 bytes)
        let nameLen = fileName.count
        bodyData.append(UInt8((nameLen >> 16) & 0xFF))
        bodyData.append(UInt8((nameLen >> 8) & 0xFF))
        bodyData.append(UInt8(nameLen & 0xFF))
        
        // Name
        bodyData.append(contentsOf: fileName.utf8)
        
        // Size (4 bytes)
        bodyData.append(UInt8((fileSize >> 24) & 0xFF))
        bodyData.append(UInt8((fileSize >> 16) & 0xFF))
        bodyData.append(UInt8((fileSize >> 8) & 0xFF))
        bodyData.append(UInt8(fileSize & 0xFF))
        
        // Reserved (6 bytes)
        bodyData.append(contentsOf: [0, 0, 0, 0, 0, 0])
        
        // Signature (16 bytes)
        bodyData.append(contentsOf: Array(repeating: 0xAB, count: 16))
        
        // Add response
        // Note: File list comes in chunks. FileController processes chunks.
        // We'll wrap this in a standard message
        let response = TestHelpers.makeResponse(for: .queryFileList, sequence: 1, body: [UInt8](bodyData))
        mockTransport.addResponse(response)
        
        // Act
        let files = try! fileController.list()
        
        // Assert
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, fileName)
        XCTAssertEqual(files[0].length, fileSize)
        XCTAssertEqual(files[0].version, 1)
        
        // Verify duration calc for version 1
        // duration = Double(fileSize) / 32.0 / 1000.0
        let expectedDuration = Double(fileSize) / 32.0 / 1000.0
        XCTAssertEqual(files[0].duration, expectedDuration, accuracy: 0.001)
    }
    
    func testListFilesReturnsEmptyWhenNoFiles() {
        // Arrange -> Count 0
        let bodyData = Data([0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00])
        let response = TestHelpers.makeResponse(for: .queryFileList, sequence: 1, body: [UInt8](bodyData))
        mockTransport.addResponse(response)
        
        // Act
        let files = try! fileController.list()
        
        // Assert
        XCTAssertTrue(files.isEmpty)
    }
    
    // MARK: - Download Tests
    
    func testDownloadSendsCorrectCommandAndReceivesData() {
        let fileName = "test.wav"
        let fileContent = Data([0xAA, 0xBB, 0xCC, 0xDD])
        
        // Response format: The device sends chunks wrapped in 0x1234 headers
        // We need to simulate that raw stream structure
        
        // Chunk 1: Header + Data
        var chunk = Data()
        // Header
        chunk.append(0x12)
        chunk.append(0x34)
        // ID (transferFile = 5)
        chunk.append(0x00)
        chunk.append(0x05)
        // Sequence
        chunk.append(contentsOf: [0, 0, 0, 0])
        // Length (4 bytes content)
        chunk.append(contentsOf: [0, 0, 0, 4])
        // Body
        chunk.append(fileContent)
        
        // We add this as a RAW response because receive() returns Data chunks
        // FileController expects these chunks to contain the frame structure
        mockTransport.addRawResponse(chunk)
        
        // Act
        let downloadedData = try! fileController.download(filename: fileName, expectedSize: UInt32(fileContent.count))
        
        // Assert
        XCTAssertEqual(downloadedData, fileContent)
        
        // Verify command sent
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1) 
        // We could verify filename in body if we decoded it, but we trust ProtocolEncoder tests
    }
    
    // MARK: - Delete Tests
    
    func testDeleteSendsCorrectCommand() {
        // Success response (0)
        mockTransport.addResponse(TestHelpers.makeResponse(for: .deleteFile, sequence: 1, body: [0]))
        
        // Act
        try! fileController.delete(name: "test.wav")
        
        // Assert
        let cmds = mockTransport.getAllSentCommands()
        XCTAssertEqual(cmds.count, 1)
        XCTAssertEqual(cmds[0][2], 0x00)
        XCTAssertEqual(cmds[0][3], 0x07) // deleteFile = 7
    }
    
    func testDeleteThrowsOnFailure() {
        // Failure response (1)
        mockTransport.addResponse(TestHelpers.makeResponse(for: .deleteFile, sequence: 1, body: [1]))
        
        XCTAssertThrowsError(try fileController.delete(name: "test.wav"))
    }
}

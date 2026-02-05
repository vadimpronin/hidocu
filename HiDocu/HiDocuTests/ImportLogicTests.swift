//
//  ImportLogicTests.swift
//  HiDocuTests
//
//  Unit tests for import logic: path resolution, repository path mapping,
//  import algorithm, and audio compatibility.
//

import XCTest
import GRDB
@testable import HiDocu

// MARK: - Mock Types

/// Mock device that returns predefined file lists and tracks download calls.
final class MockDeviceFileProvider: DeviceFileProvider {
    var connectionInfo: DeviceConnectionInfo? = DeviceConnectionInfo(
        serialNumber: "TEST-001",
        model: .h1,
        firmwareVersion: "1.0.0",
        firmwareNumber: 100
    )

    var filesToReturn: [DeviceFileInfo] = []
    var downloadedFiles: [(filename: String, toPath: URL)] = []
    var downloadShouldFail = false

    func listFiles() async throws -> [DeviceFileInfo] {
        filesToReturn
    }

    /// Size of the WAV file the mock writes during download.
    /// Must match the `size` in the corresponding `DeviceFileInfo`.
    var downloadFileSize: Int = 88244

    func downloadFile(filename: String, expectedSize: Int, toPath: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        if downloadShouldFail {
            throw ImportError.downloadFailed("Mock download failure")
        }
        downloadedFiles.append((filename: filename, toPath: toPath))
        progress(Int64(expectedSize), Int64(expectedSize))
        // Write a valid WAV whose on-disk size matches downloadFileSize
        let wavData = createMinimalWAV(sizeBytes: downloadFileSize)
        try wavData.write(to: toPath)
    }
}

/// In-memory recording repository that tracks call order for verification.
final class MockRecordingRepository: RecordingRepository, @unchecked Sendable {
    /// Ordered log of method calls (e.g. "fetchByFilename", "insert", "updateFilePath")
    var callOrder: [String] = []

    /// In-memory storage keyed by id
    private var recordings: [Int64: Recording] = [:]
    private var nextId: Int64 = 1

    // Pre-configured return values
    var fetchByFilenameResult: Recording?

    func fetchAll(filterStatus: RecordingStatus?, sortBy: RecordingSortField, ascending: Bool) async throws -> [Recording] {
        callOrder.append("fetchAll")
        var result = Array(recordings.values)
        if let status = filterStatus {
            result = result.filter { $0.status == status }
        }
        return result
    }

    func fetchById(_ id: Int64) async throws -> Recording? {
        callOrder.append("fetchById")
        return recordings[id]
    }

    func fetchByFilename(_ filename: String) async throws -> Recording? {
        callOrder.append("fetchByFilename")
        if let preset = fetchByFilenameResult, preset.filename == filename {
            return preset
        }
        return recordings.values.first { $0.filename == filename }
    }

    func insert(_ recording: Recording) async throws -> Recording {
        callOrder.append("insert")
        let id = nextId
        nextId += 1
        let stored = Recording(
            id: id,
            filename: recording.filename,
            filepath: recording.filepath,
            title: recording.title,
            durationSeconds: recording.durationSeconds,
            fileSizeBytes: recording.fileSizeBytes,
            createdAt: recording.createdAt,
            modifiedAt: recording.modifiedAt,
            deviceSerial: recording.deviceSerial,
            deviceModel: recording.deviceModel,
            recordingMode: recording.recordingMode,
            status: recording.status,
            playbackPositionSeconds: recording.playbackPositionSeconds
        )
        recordings[id] = stored
        return stored
    }

    func update(_ recording: Recording) async throws {
        callOrder.append("update")
        recordings[recording.id] = recording
    }

    func delete(id: Int64) async throws {
        callOrder.append("delete")
        recordings.removeValue(forKey: id)
    }

    func updatePlaybackPosition(id: Int64, seconds: Int) async throws {
        callOrder.append("updatePlaybackPosition")
    }

    func updateStatus(id: Int64, status: RecordingStatus) async throws {
        callOrder.append("updateStatus")
    }

    func search(query: String) async throws -> [Recording] {
        callOrder.append("search")
        return recordings.values.filter {
            $0.filename.contains(query) || ($0.title?.contains(query) ?? false)
        }
    }

    func observeAll(filterStatus: RecordingStatus?, sortBy: RecordingSortField, ascending: Bool) -> AsyncThrowingStream<[Recording], Error> {
        callOrder.append("observeAll")
        return AsyncThrowingStream { continuation in
            continuation.yield(Array(recordings.values))
            continuation.finish()
        }
    }

    func exists(filename: String, sizeBytes: Int) async throws -> Bool {
        callOrder.append("exists")
        return recordings.values.contains { $0.filename == filename && $0.fileSizeBytes == sizeBytes }
    }

    func markAsDownloaded(id: Int64, relativePath: String) async throws {
        callOrder.append("markAsDownloaded")
    }

    func updateFilePath(id: Int64, newRelativePath: String, newFilename: String) async throws {
        callOrder.append("updateFilePath")
        if let rec = recordings[id] {
            recordings[id] = Recording(
                id: rec.id,
                filename: newFilename,
                filepath: newRelativePath,
                title: rec.title,
                durationSeconds: rec.durationSeconds,
                fileSizeBytes: rec.fileSizeBytes,
                createdAt: rec.createdAt,
                modifiedAt: rec.modifiedAt,
                deviceSerial: rec.deviceSerial,
                deviceModel: rec.deviceModel,
                recordingMode: rec.recordingMode,
                status: rec.status,
                playbackPositionSeconds: rec.playbackPositionSeconds
            )
        }
    }
}

// MARK: - Test Helper

/// Create a minimal valid WAV file data of approximately the given size.
/// Produces a 44-byte header + silence data that AVURLAsset can read.
func createMinimalWAV(sizeBytes: Int) -> Data {
    let dataSize = max(sizeBytes - 44, 0)
    let fileSize = UInt32(dataSize + 36)
    let sampleRate: UInt32 = 44100
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign: UInt16 = channels * (bitsPerSample / 8)

    var header = Data()
    // RIFF header
    header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
    header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    // fmt subchunk
    header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // subchunk size
    header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
    header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
    // data subchunk
    header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

    // Silence
    header.append(Data(count: dataSize))
    return header
}

/// Write a test audio file at the given URL with specific size.
@discardableResult
func createTestAudioFile(at url: URL, sizeBytes: Int) throws -> URL {
    let data = createMinimalWAV(sizeBytes: sizeBytes)
    try data.write(to: url)
    return url
}

// MARK: - Category A: FileSystemService Path Resolution

final class FileSystemPathTests: XCTestCase {

    var service: FileSystemService!
    private var tempDir: URL!

    override func setUpWithError() throws {
        service = FileSystemService()
        // Use a temp directory as the "storage" directory for deterministic tests.
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HiDocuPathTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        service = nil
    }

    /// relativePath(for:) extracts filename from an absolute URL within the storage directory.
    func testRelativePathStripsStoragePrefix() {
        // The default storageDirectory is set during init; use it directly.
        guard let storageDir = service.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }
        let fileURL = storageDir.appendingPathComponent("Recording.hda")
        let relative = service.relativePath(for: fileURL)
        XCTAssertEqual(relative, "Recording.hda")
    }

    /// relativePath(for:) returns nil for URLs outside the storage directory.
    func testRelativePathReturnsNilForOutsideURL() {
        let outsideURL = URL(fileURLWithPath: "/tmp/not-in-storage/file.hda")
        let relative = service.relativePath(for: outsideURL)
        XCTAssertNil(relative)
    }

    /// resolve(relativePath:) joins the storage directory with a relative path.
    func testResolveRelativePath() throws {
        guard let storageDir = service.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }
        let resolved = try service.resolve(relativePath: "Recording.hda")
        XCTAssertEqual(resolved.standardizedFileURL, storageDir.appendingPathComponent("Recording.hda").standardizedFileURL)
    }

    /// generateBackupFilename returns "Recording_backup_1.hda" for a new file.
    func testGenerateBackupFilename() throws {
        let backup = try service.generateBackupFilename(for: "Recording.hda")
        XCTAssertEqual(backup, "Recording_backup_1.hda")
    }

    /// generateBackupFilename increments the counter when a backup already exists on disk.
    func testGenerateBackupFilenameIncrementsWhenExists() throws {
        guard let storageDir = service.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }

        // Ensure storage dir exists
        try service.ensureStorageDirectoryExists()

        // Create "Recording_backup_1.hda" in storage so it's "taken"
        let existing = storageDir.appendingPathComponent("Recording_backup_1.hda")
        try Data("test".utf8).write(to: existing)

        let backup = try service.generateBackupFilename(for: "Recording.hda")
        XCTAssertEqual(backup, "Recording_backup_2.hda")

        // Cleanup
        try? FileManager.default.removeItem(at: existing)
    }
}

// MARK: - Category B: Repository Path Mapping

final class RepositoryPathMappingTests: XCTestCase {

    var db: DatabaseManager!
    var fileSystemService: FileSystemService!
    var repository: SQLiteRecordingRepository!

    override func setUpWithError() throws {
        db = try DatabaseManager(inMemory: true)
        fileSystemService = FileSystemService()
        repository = SQLiteRecordingRepository(databaseManager: db, fileSystemService: fileSystemService)
    }

    override func tearDownWithError() throws {
        repository = nil
        fileSystemService = nil
        db = nil
    }

    /// insert() converts absolute filepath to relative in the database.
    func testRepositoryInsertStoresRelativePath() async throws {
        guard let storageDir = fileSystemService.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }

        let absolutePath = storageDir.appendingPathComponent("test.hda").path
        let recording = Recording(
            filename: "test.hda",
            filepath: absolutePath,
            status: .downloaded
        )

        _ = try await repository.insert(recording)

        // Verify the stored filepath in DB is relative (not a full absolute path)
        let raw = try db.read { database in
            try String.fetchOne(database, sql: "SELECT filepath FROM recordings WHERE filename = ?", arguments: ["test.hda"])
        }
        let storedPath = try XCTUnwrap(raw, "filepath should not be nil in DB")
        // The stored path should be relative (just the filename, not the full absolute path)
        XCTAssertFalse(storedPath.hasPrefix("/"), "DB should store relative path, not absolute. Got: \(storedPath)")
        XCTAssertTrue(storedPath.hasSuffix("test.hda"), "Stored path should end with filename")
    }

    /// fetch converts relative path back to absolute in the domain model.
    func testRepositoryFetchReturnsAbsolutePath() async throws {
        guard let storageDir = fileSystemService.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }

        let absolutePath = storageDir.appendingPathComponent("fetch_test.hda").path
        let recording = Recording(
            filename: "fetch_test.hda",
            filepath: absolutePath,
            status: .downloaded
        )

        _ = try await repository.insert(recording)

        // Use fetchByFilename since insert() may not capture auto-generated id
        let fetched = try await repository.fetchByFilename("fetch_test.hda")
        let unwrapped = try XCTUnwrap(fetched, "fetchByFilename should return the inserted recording")
        // The fetched filepath should be absolute (resolved from relative)
        XCTAssertTrue(unwrapped.filepath.hasPrefix("/"), "Fetched filepath should be absolute")
        XCTAssertTrue(unwrapped.filepath.hasSuffix("fetch_test.hda"))
    }

    /// exists() returns true when filename and size match, false otherwise.
    func testRepositoryExistsWithMatchingSize() async throws {
        guard let storageDir = fileSystemService.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }

        let recording = Recording(
            filename: "size_test.hda",
            filepath: storageDir.appendingPathComponent("size_test.hda").path,
            fileSizeBytes: 5000,
            status: .downloaded
        )

        _ = try await repository.insert(recording)

        let matchesExact = try await repository.exists(filename: "size_test.hda", sizeBytes: 5000)
        XCTAssertTrue(matchesExact, "Should match when filename and size are equal")

        let matchesWrongSize = try await repository.exists(filename: "size_test.hda", sizeBytes: 9999)
        XCTAssertFalse(matchesWrongSize, "Should not match when size differs")
    }

    /// updateFilePath() changes both filename and filepath in the database.
    func testRepositoryUpdateFilePath() async throws {
        guard let storageDir = fileSystemService.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }

        let recording = Recording(
            filename: "original.hda",
            filepath: storageDir.appendingPathComponent("original.hda").path,
            status: .downloaded
        )

        _ = try await repository.insert(recording)

        // Look up the auto-generated id via direct DB query
        let recordId = try db.read { database in
            try Int64.fetchOne(database, sql: "SELECT id FROM recordings WHERE filename = ?", arguments: ["original.hda"])
        }
        let id = try XCTUnwrap(recordId)

        try await repository.updateFilePath(
            id: id,
            newRelativePath: "original_backup_1.hda",
            newFilename: "original_backup_1.hda"
        )

        // Fetch by new filename since we changed it
        let updatedOpt = try await repository.fetchByFilename("original_backup_1.hda")
        let updated = try XCTUnwrap(updatedOpt)
        XCTAssertEqual(updated.filename, "original_backup_1.hda")
        XCTAssertTrue(updated.filepath.hasSuffix("original_backup_1.hda"))
    }
}

// MARK: - Category C: Import Algorithm Logic

final class ImportAlgorithmTests: XCTestCase {

    var mockDevice: MockDeviceFileProvider!
    var mockRepo: MockRecordingRepository!
    var fileSystemService: FileSystemService!
    var audioService: AudioCompatibilityService!
    var importService: RecordingImportService!

    override func setUpWithError() throws {
        mockDevice = MockDeviceFileProvider()
        mockRepo = MockRecordingRepository()
        fileSystemService = FileSystemService()
        audioService = AudioCompatibilityService()

        // Ensure storage directory exists for the import service to write into
        try fileSystemService.ensureStorageDirectoryExists()

        importService = RecordingImportService(
            deviceService: mockDevice,
            fileSystemService: fileSystemService,
            audioService: audioService,
            repository: mockRepo
        )
    }

    override func tearDownWithError() throws {
        importService = nil
        mockDevice = nil
        mockRepo = nil
        fileSystemService = nil
        audioService = nil
    }

    /// When a file exists with matching size, import should skip (no insert).
    func testImportSkipsFileWithMatchingSize() async {
        let existingRecording = Recording(
            id: 1,
            filename: "Recording.hda",
            filepath: "/dummy/Recording.hda",
            fileSizeBytes: 2048,
            status: .downloaded
        )
        mockRepo.fetchByFilenameResult = existingRecording

        mockDevice.filesToReturn = [
            DeviceFileInfo(filename: "Recording.hda", size: 2048, durationSeconds: 60, createdAt: Date(), mode: .call)
        ]

        importService.importFromDevice()
        // Wait for async import to complete
        while importService.isImporting {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(mockRepo.callOrder.contains("insert"), "Should not insert when size matches")
        XCTAssertFalse(mockRepo.callOrder.contains("updateFilePath"), "Should not resolve conflict when size matches")
    }

    /// When existing.fileSizeBytes is nil, import should treat it as "already imported" (skip).
    /// This validates the Step 2 bug fix.
    func testImportSkipsFileWithNilSize() async {
        let existingRecording = Recording(
            id: 1,
            filename: "Recording.hda",
            filepath: "/dummy/Recording.hda",
            fileSizeBytes: nil, // nil size metadata
            status: .downloaded
        )
        mockRepo.fetchByFilenameResult = existingRecording

        mockDevice.filesToReturn = [
            DeviceFileInfo(filename: "Recording.hda", size: 2048, durationSeconds: 60, createdAt: Date(), mode: .call)
        ]

        importService.importFromDevice()
        // Wait for async import to complete
        while importService.isImporting {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(mockRepo.callOrder.contains("insert"), "Should not insert when existing size is nil (treated as imported)")
        XCTAssertFalse(mockRepo.callOrder.contains("updateFilePath"), "Should not resolve conflict when existing size is nil")
    }

    /// CRITICAL: During conflict resolution, updateFilePath must appear BEFORE insert
    /// in the call order (required by UNIQUE constraint on filename).
    func testImportConflictResolutionOrderIsCorrect() async throws {
        guard let storageDir = fileSystemService.storageDirectory else {
            XCTFail("storageDirectory should not be nil")
            return
        }

        let wavSize = 88244 // 1-second WAV (44-byte header + 88200 PCM data)
        mockDevice.downloadFileSize = wavSize

        // Create the physical file so renameFile succeeds
        let originalURL = storageDir.appendingPathComponent("Conflict.wav")
        try createTestAudioFile(at: originalURL, sizeBytes: wavSize)

        let existingRecording = Recording(
            id: 1,
            filename: "Conflict.wav",
            filepath: originalURL.path,
            fileSizeBytes: 500, // Different size -> triggers conflict
            status: .downloaded
        )
        mockRepo.fetchByFilenameResult = existingRecording

        mockDevice.filesToReturn = [
            DeviceFileInfo(filename: "Conflict.wav", size: wavSize, durationSeconds: 60, createdAt: Date(), mode: .call)
        ]

        importService.importFromDevice()
        // Wait for async import to complete
        while importService.isImporting {
            try? await Task.sleep(for: .milliseconds(10))
        }

        // Find positions
        let updateIdx = mockRepo.callOrder.firstIndex(of: "updateFilePath")
        let insertIdx = mockRepo.callOrder.firstIndex(of: "insert")

        XCTAssertNotNil(updateIdx, "updateFilePath should have been called")
        XCTAssertNotNil(insertIdx, "insert should have been called")

        if let u = updateIdx, let i = insertIdx {
            XCTAssertTrue(u < i, "updateFilePath (index \(u)) must come before insert (index \(i)) — UNIQUE constraint requirement")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: storageDir.appendingPathComponent("Conflict_backup_1.wav"))
        try? FileManager.default.removeItem(at: storageDir.appendingPathComponent("Conflict.wav"))
    }

    /// A completely new file (not in repo) should be downloaded, validated, and inserted.
    func testImportDownloadsNewFile() async {
        let wavSize = 88244
        mockDevice.downloadFileSize = wavSize
        mockRepo.fetchByFilenameResult = nil // File does not exist

        mockDevice.filesToReturn = [
            DeviceFileInfo(filename: "NewFile.wav", size: wavSize, durationSeconds: 30, createdAt: Date(), mode: .recording)
        ]

        importService.importFromDevice()
        // Wait for async import to complete
        while importService.isImporting {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(mockDevice.downloadedFiles.count, 1, "Should download the new file")
        XCTAssertEqual(mockDevice.downloadedFiles.first?.filename, "NewFile.wav")
        XCTAssertTrue(mockRepo.callOrder.contains("insert"), "Should insert the new recording")

        // Cleanup
        guard let storageDir = fileSystemService.storageDirectory else { return }
        try? FileManager.default.removeItem(at: storageDir.appendingPathComponent("NewFile.wav"))
    }
}

// MARK: - Category D: AudioCompatibilityService

final class AudioCompatibilityTests: XCTestCase {

    var audioService: AudioCompatibilityService!
    private var tempDir: URL!

    override func setUpWithError() throws {
        audioService = AudioCompatibilityService()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HiDocuAudioTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        audioService = nil
    }

    /// prepareForPlayback with .hda input creates an .mp3 hard link.
    func testPrepareForPlaybackHdaCreatesMp3Link() async throws {
        let hdaURL = tempDir.appendingPathComponent("TestRecording.hda")
        try createTestAudioFile(at: hdaURL, sizeBytes: 4096)

        let playbackURL = try await audioService.prepareForPlayback(url: hdaURL)

        XCTAssertEqual(playbackURL.pathExtension, "mp3", "Should produce an .mp3 URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: playbackURL.path), "The .mp3 file should exist on disk")
    }

    /// prepareForPlayback with a standard extension (.mp3) returns the original URL.
    func testPrepareForPlaybackStandardExtensionReturnsOriginal() async throws {
        let mp3URL = tempDir.appendingPathComponent("Standard.mp3")
        try createTestAudioFile(at: mp3URL, sizeBytes: 2048)

        let playbackURL = try await audioService.prepareForPlayback(url: mp3URL)

        XCTAssertEqual(playbackURL, mp3URL, "Standard extensions should return the original URL")
    }
}

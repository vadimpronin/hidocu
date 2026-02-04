//
//  TranscriptionTests.swift
//  HiDocuTests
//
//  Unit tests for SQLiteTranscriptionRepository.
//

import XCTest
import GRDB
@testable import HiDocu

final class TranscriptionTests: XCTestCase {

    var db: DatabaseManager!
    var repo: SQLiteTranscriptionRepository!
    var recordingId: Int64!

    override func setUpWithError() throws {
        db = try DatabaseManager(inMemory: true)
        repo = SQLiteTranscriptionRepository(databaseManager: db)

        // Insert a test recording
        recordingId = try db.write { database in
            try database.execute(
                sql: "INSERT INTO recordings (filename, filepath, status) VALUES (?, ?, ?)",
                arguments: ["test.hda", "/path/test.hda", "new"]
            )
            return database.lastInsertedRowID
        }
    }

    override func tearDownWithError() throws {
        repo = nil
        db = nil
    }

    // MARK: - Insert Tests

    func testInsertFirstVariantSetsPrimary() async throws {
        let transcription = Transcription(
            recordingId: recordingId,
            fullText: "Hello world",
            title: "V1",
            isPrimary: false  // explicitly false
        )

        let inserted = try await repo.insert(transcription)

        XCTAssertTrue(inserted.isPrimary, "First variant should be auto-set to primary")
        XCTAssertEqual(inserted.title, "V1")
        XCTAssertEqual(inserted.fullText, "Hello world")
        XCTAssertNotEqual(inserted.id, 0)
    }

    func testInsertSecondVariantNotPrimary() async throws {
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V1"))
        let second = try await repo.insert(Transcription(recordingId: recordingId, title: "V2"))

        XCTAssertFalse(second.isPrimary, "Second variant should not be primary")
    }

    func testMaxFiveVariantsEnforced() async throws {
        for i in 1...5 {
            _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V\(i)"))
        }

        do {
            _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V6"))
            XCTFail("Should have thrown maxVariantsReached")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .maxVariantsReached)
        }
    }

    // MARK: - Fetch Tests

    func testFetchForRecordingOrdersPrimaryFirst() async throws {
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V1"))
        let v2 = try await repo.insert(Transcription(recordingId: recordingId, title: "V2"))
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V3"))

        // Set V2 as primary
        try await repo.setPrimary(id: v2.id, recordingId: recordingId)

        let variants = try await repo.fetchForRecording(recordingId)

        XCTAssertEqual(variants.count, 3)
        XCTAssertEqual(variants.first?.id, v2.id, "Primary should be first")
        XCTAssertTrue(variants.first?.isPrimary ?? false)
    }

    func testFetchById() async throws {
        let inserted = try await repo.insert(Transcription(recordingId: recordingId, title: "Find me"))

        let found = try await repo.fetchById(inserted.id)

        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Find me")
    }

    func testFetchPrimary() async throws {
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "Primary"))
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "Other"))

        let primary = try await repo.fetchPrimary(recordingId: recordingId)

        XCTAssertNotNil(primary)
        XCTAssertEqual(primary?.title, "Primary")
        XCTAssertTrue(primary?.isPrimary ?? false)
    }

    func testCountForRecording() async throws {
        let initialCount = try await repo.countForRecording(recordingId)
        XCTAssertEqual(initialCount, 0)

        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V1"))
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V2"))

        let afterCount = try await repo.countForRecording(recordingId)
        XCTAssertEqual(afterCount, 2)
    }

    // MARK: - Update Tests

    func testUpdateTranscription() async throws {
        var inserted = try await repo.insert(Transcription(
            recordingId: recordingId,
            fullText: "Original",
            title: "V1"
        ))

        inserted.fullText = "Updated text"
        try await repo.update(inserted)

        let fetched = try await repo.fetchById(inserted.id)
        XCTAssertEqual(fetched?.fullText, "Updated text")
    }

    // MARK: - Delete Tests

    func testDeleteNonPrimaryVariant() async throws {
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V1"))
        let v2 = try await repo.insert(Transcription(recordingId: recordingId, title: "V2"))

        try await repo.delete(id: v2.id)

        let variants = try await repo.fetchForRecording(recordingId)
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants.first?.title, "V1")
        XCTAssertTrue(variants.first?.isPrimary ?? false)
    }

    func testDeletePrimaryAutoPromotesOldest() async throws {
        let v1 = try await repo.insert(Transcription(recordingId: recordingId, title: "V1"))
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V2"))
        _ = try await repo.insert(Transcription(recordingId: recordingId, title: "V3"))

        // V1 is primary (first inserted). Delete it.
        try await repo.delete(id: v1.id)

        let variants = try await repo.fetchForRecording(recordingId)
        XCTAssertEqual(variants.count, 2)

        // The oldest remaining (V2) should now be primary
        let primary = variants.first { $0.isPrimary }
        XCTAssertNotNil(primary)
        XCTAssertEqual(primary?.title, "V2")
    }

    func testDeleteNotFoundThrows() async throws {
        do {
            try await repo.delete(id: 99999)
            XCTFail("Should throw notFound")
        } catch let error as TranscriptionError {
            XCTAssertEqual(error, .notFound)
        }
    }

    // MARK: - Set Primary Tests

    func testSetPrimaryAtomicity() async throws {
        let v1 = try await repo.insert(Transcription(recordingId: recordingId, title: "V1"))
        let v2 = try await repo.insert(Transcription(recordingId: recordingId, title: "V2"))
        let v3 = try await repo.insert(Transcription(recordingId: recordingId, title: "V3"))

        // V1 is primary. Set V3 as primary.
        try await repo.setPrimary(id: v3.id, recordingId: recordingId)

        let variants = try await repo.fetchForRecording(recordingId)
        let primaries = variants.filter { $0.isPrimary }

        XCTAssertEqual(primaries.count, 1, "Only one variant should be primary")
        XCTAssertEqual(primaries.first?.id, v3.id)
    }

    // MARK: - CASCADE Delete Tests

    func testCascadeDeleteRecordingRemovesTranscriptionsAndSegments() async throws {
        let t = try await repo.insert(Transcription(recordingId: recordingId, title: "V1", isPrimary: true))

        // Insert a segment
        try await repo.insertSegments([
            Segment(transcriptionId: t.id, startTimeMs: 0, endTimeMs: 1000, text: "Hello")
        ], transcriptionId: t.id)

        // Verify segment exists
        let segments = try await repo.fetchSegments(transcriptionId: t.id)
        XCTAssertEqual(segments.count, 1)

        // Delete the recording
        try db.write { database in
            try database.execute(sql: "DELETE FROM recordings WHERE id = ?", arguments: [self.recordingId!])
        }

        // Transcriptions should be gone
        let transcriptions = try await repo.fetchForRecording(recordingId)
        XCTAssertEqual(transcriptions.count, 0)

        // Segments should be gone (cascaded through transcription)
        let remainingSegments = try await repo.fetchSegments(transcriptionId: t.id)
        XCTAssertEqual(remainingSegments.count, 0)
    }

    // MARK: - Search Tests

    func testSearchByText() async throws {
        _ = try await repo.insert(Transcription(recordingId: recordingId, fullText: "The quick brown fox", title: "V1"))
        _ = try await repo.insert(Transcription(recordingId: recordingId, fullText: "Lazy dog", title: "V2"))

        let results = try await repo.search(query: "brown fox")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "V1")
    }

    // MARK: - Segment Tests

    func testInsertAndFetchSegments() async throws {
        let t = try await repo.insert(Transcription(recordingId: recordingId, title: "V1"))

        try await repo.insertSegments([
            Segment(transcriptionId: t.id, startTimeMs: 0, endTimeMs: 1000, text: "Hello"),
            Segment(transcriptionId: t.id, startTimeMs: 1000, endTimeMs: 2000, text: "World")
        ], transcriptionId: t.id)

        let segments = try await repo.fetchSegments(transcriptionId: t.id)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.first?.text, "Hello")
        XCTAssertEqual(segments.last?.text, "World")
    }
}

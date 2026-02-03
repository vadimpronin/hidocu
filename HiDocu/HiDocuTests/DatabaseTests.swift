//
//  DatabaseTests.swift
//  HiDocuTests
//
//  Unit tests for DatabaseManager and schema migrations.
//

import XCTest
import GRDB
@testable import HiDocu

final class DatabaseTests: XCTestCase {
    
    var db: DatabaseManager!
    
    override func setUpWithError() throws {
        // Create fresh in-memory database for each test
        db = try DatabaseManager(inMemory: true)
    }
    
    override func tearDownWithError() throws {
        db = nil
    }
    
    // MARK: - Schema Tests
    
    func testRecordingsTableExists() throws {
        try db.read { database in
            let exists = try database.tableExists("recordings")
            XCTAssertTrue(exists, "recordings table should exist")
        }
    }
    
    func testTranscriptionsTableExists() throws {
        try db.read { database in
            let exists = try database.tableExists("transcriptions")
            XCTAssertTrue(exists, "transcriptions table should exist")
        }
    }
    
    func testSegmentsTableExists() throws {
        try db.read { database in
            let exists = try database.tableExists("segments")
            XCTAssertTrue(exists, "segments table should exist")
        }
    }
    
    func testApiLogsTableExists() throws {
        try db.read { database in
            let exists = try database.tableExists("api_logs")
            XCTAssertTrue(exists, "api_logs table should exist")
        }
    }
    
    func testSettingsTableExists() throws {
        try db.read { database in
            let exists = try database.tableExists("settings")
            XCTAssertTrue(exists, "settings table should exist")
        }
    }
    
    // MARK: - Foreign Key Tests
    
    func testForeignKeysEnabled() throws {
        try db.read { database in
            let result = try Int.fetchOne(database, sql: "PRAGMA foreign_keys")
            XCTAssertEqual(result, 1, "foreign_keys should be enabled")
        }
    }
    
    // MARK: - CRUD Tests
    
    func testRecordingInsertAndFetch() throws {
        // Insert a recording using raw SQL
        try db.write { database in
            try database.execute(
                sql: """
                    INSERT INTO recordings (filename, filepath, title, status)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: ["test.hda", "/path/to/test.hda", "Test Recording", "new"]
            )
        }
        
        // Fetch it back
        let count = try db.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM recordings")
        }
        
        XCTAssertEqual(count, 1, "Should have inserted 1 recording")
    }
    
    func testApiLogInsert() throws {
        // Insert an API log entry
        try db.write { database in
            try database.execute(
                sql: """
                    INSERT INTO api_logs (provider, model, request_type, status)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: ["openai", "whisper-1", "transcription", "success"]
            )
        }
        
        let count = try db.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM api_logs")
        }
        
        XCTAssertEqual(count, 1, "Should have inserted 1 api_log entry")
    }
    
    func testSettingsKeyValue() throws {
        // Insert a setting
        try db.write { database in
            try database.execute(
                sql: "INSERT INTO settings (key, value) VALUES (?, ?)",
                arguments: ["theme", "dark"]
            )
        }
        
        // Fetch it
        let value = try db.read { database in
            try String.fetchOne(database, sql: "SELECT value FROM settings WHERE key = ?", arguments: ["theme"])
        }
        
        XCTAssertEqual(value, "dark", "Should retrieve correct setting value")
    }
    
    // MARK: - Index Tests
    
    func testRecordingsIndexesExist() throws {
        try db.read { database in
            let indexes = try database.indexes(on: "recordings")
            let indexNames = indexes.map { $0.name }
            
            XCTAssertTrue(indexNames.contains("idx_recordings_filename"), "filename index should exist")
            XCTAssertTrue(indexNames.contains("idx_recordings_title"), "title index should exist")
            XCTAssertTrue(indexNames.contains("idx_recordings_created_at"), "created_at index should exist")
            XCTAssertTrue(indexNames.contains("idx_recordings_status"), "status index should exist")
        }
    }
}

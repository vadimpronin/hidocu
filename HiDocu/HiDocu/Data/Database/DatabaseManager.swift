//
//  DatabaseManager.swift
//  HiDocu
//
//  SQLite database engine using GRDB with proper configuration.
//

import Foundation
import GRDB

/// Manages the SQLite database connection and migrations.
/// Uses GRDB with WAL mode and foreign key constraints.
final class DatabaseManager: Sendable {
    
    /// The database connection pool (thread-safe)
    let dbPool: DatabasePool
    
    /// Database file path
    let databasePath: String
    
    /// Initialize the database manager.
    /// Creates the database file and runs migrations if needed.
    init() throws {
        // Get Application Support directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let hidocuDir = appSupport.appendingPathComponent("HiDocu", isDirectory: true)
        
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: hidocuDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        let dbURL = hidocuDir.appendingPathComponent("hidocu.sqlite")
        self.databasePath = dbURL.path
        
        AppLogger.database.info("Database path: \(self.databasePath)")
        
        // Configure GRDB
        var config = Configuration()
        
        // Enable foreign keys on every connection (CRITICAL)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        
        // Create database pool
        self.dbPool = try DatabasePool(path: databasePath, configuration: config)
        
        // Set WAL mode for better concurrency
        try dbPool.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        
        AppLogger.database.info("Database initialized with WAL mode and foreign keys enabled")
        
        // Run migrations
        try Self.migrator.migrate(dbPool)
        
        AppLogger.database.info("Database migrations complete")
    }
    
    // MARK: - Migrations
    
    /// Database migrator with all schema versions
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // Always re-run migrations in development
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        
        // v1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // recordings table
            try db.execute(sql: """
                CREATE TABLE recordings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    filename TEXT UNIQUE NOT NULL,
                    filepath TEXT NOT NULL,
                    title TEXT,
                    duration_seconds INTEGER,
                    file_size_bytes INTEGER,
                    created_at DATETIME,
                    modified_at DATETIME,
                    device_serial TEXT,
                    device_model TEXT,
                    recording_mode TEXT,
                    status TEXT,
                    playback_position_seconds INTEGER DEFAULT 0
                )
                """)
            
            // Indexes for search optimization
            try db.execute(sql: """
                CREATE INDEX idx_recordings_filename ON recordings(filename)
                """)
            try db.execute(sql: """
                CREATE INDEX idx_recordings_title ON recordings(title)
                """)
            try db.execute(sql: """
                CREATE INDEX idx_recordings_created_at ON recordings(created_at)
                """)
            try db.execute(sql: """
                CREATE INDEX idx_recordings_status ON recordings(status)
                """)
            
            // transcriptions table (1:1 with recordings)
            try db.execute(sql: """
                CREATE TABLE transcriptions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recording_id INTEGER NOT NULL UNIQUE REFERENCES recordings(id) ON DELETE CASCADE,
                    full_text TEXT,
                    language TEXT,
                    model_used TEXT,
                    transcribed_at DATETIME,
                    confidence_score REAL
                )
                """)
            
            // segments table (1:N with transcriptions) - for future use
            try db.execute(sql: """
                CREATE TABLE segments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    transcription_id INTEGER NOT NULL REFERENCES transcriptions(id) ON DELETE CASCADE,
                    start_time_ms INTEGER NOT NULL,
                    end_time_ms INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    speaker_label TEXT,
                    confidence REAL
                )
                """)
            try db.execute(sql: """
                CREATE INDEX idx_segments_transcription ON segments(transcription_id)
                """)
            
            // api_logs table - for tracking AI API usage and costs
            try db.execute(sql: """
                CREATE TABLE api_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recording_id INTEGER REFERENCES recordings(id) ON DELETE SET NULL,
                    provider TEXT NOT NULL,
                    model TEXT NOT NULL,
                    request_type TEXT NOT NULL,
                    input_tokens INTEGER,
                    output_tokens INTEGER,
                    cost_usd REAL,
                    duration_ms INTEGER,
                    status TEXT NOT NULL,
                    error_message TEXT,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: """
                CREATE INDEX idx_api_logs_recording ON api_logs(recording_id)
                """)
            try db.execute(sql: """
                CREATE INDEX idx_api_logs_created_at ON api_logs(created_at)
                """)
            
            // settings table - key-value store for app configuration
            try db.execute(sql: """
                CREATE TABLE settings (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
                """)
            
            AppLogger.database.info("Migration v1_initial complete")
        }
        
        return migrator
    }
    
    // MARK: - Convenience Methods
    
    /// Execute a read operation
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbPool.read(block)
    }
    
    /// Execute a write operation
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbPool.write(block)
    }
    
    /// Execute an async read operation
    func asyncRead<T: Sendable>(
        _ block: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        try await dbPool.read(block)
    }
    
    /// Execute an async write operation
    func asyncWrite<T: Sendable>(
        _ block: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        try await dbPool.write(block)
    }
}

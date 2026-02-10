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
    
    /// Database file path (nil for in-memory databases)
    let databasePath: String?
    
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
        
        AppLogger.database.info("Database path: \(self.databasePath ?? "in-memory")")
        
        // Configure GRDB
        var config = Configuration()
        
        // Enable foreign keys on every connection (CRITICAL)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        
        // Create database pool
        self.dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        
        // Set WAL mode for better concurrency
        try dbPool.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        
        AppLogger.database.info("Database initialized with WAL mode and foreign keys enabled")
        
        // Run migrations
        try Self.migrator.migrate(dbPool)
        
        AppLogger.database.info("Database migrations complete")
    }
    
    /// Initialize a temporary file-based database for unit testing.
    /// Uses a unique temp file per instance so tests remain isolated.
    /// - Parameter inMemory: Must be true (exists for disambiguation)
    init(inMemory: Bool) throws {
        precondition(inMemory, "Use init() for file-based database")

        let tempPath = NSTemporaryDirectory() + "hidocu_test_\(UUID().uuidString).sqlite"
        self.databasePath = tempPath

        // Configure GRDB
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        // Use a temp file — DatabasePool requires WAL which needs a real file
        self.dbPool = try DatabasePool(path: tempPath, configuration: config)

        // Run migrations
        try Self.migrator.migrate(dbPool)
    }
    
    // MARK: - Migrations
    
    /// Database migrator with all schema versions
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // Always re-run migrations in development
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // Single consolidated migration — final schema
        migrator.registerMigration("v1_initial") { db in

            // -- folders --
            try db.execute(sql: """
                CREATE TABLE folders (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    transcription_context TEXT,
                    categorization_context TEXT,
                    prefer_summary INTEGER NOT NULL DEFAULT 1,
                    minimize_before_llm INTEGER NOT NULL DEFAULT 0,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    disk_path TEXT,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)

            // -- documents --
            try db.execute(sql: """
                CREATE TABLE documents (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
                    title TEXT NOT NULL DEFAULT 'Untitled',
                    document_type TEXT NOT NULL DEFAULT 'markdown',
                    disk_path TEXT NOT NULL UNIQUE,
                    body_preview TEXT,
                    summary_text TEXT,
                    body_hash TEXT,
                    summary_hash TEXT,
                    prefer_summary INTEGER NOT NULL DEFAULT 0,
                    minimize_before_llm INTEGER NOT NULL DEFAULT 0,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    summary_generated_at DATETIME,
                    summary_model TEXT,
                    summary_edited INTEGER NOT NULL DEFAULT 0,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_documents_folder_sort ON documents(folder_id, sort_order)")

            // -- recording_sources --
            try db.execute(sql: """
                CREATE TABLE recording_sources (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    unique_identifier TEXT,
                    auto_import_enabled INTEGER NOT NULL DEFAULT 0,
                    is_active INTEGER NOT NULL DEFAULT 1,
                    directory TEXT NOT NULL,
                    device_model TEXT,
                    last_seen_at DATETIME,
                    last_synced_at DATETIME,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_recording_sources_unique_id
                    ON recording_sources(unique_identifier) WHERE unique_identifier IS NOT NULL
                """)

            // -- recordings --
            try db.execute(sql: """
                CREATE TABLE recordings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    filename TEXT NOT NULL,
                    filepath TEXT NOT NULL,
                    title TEXT,
                    file_size_bytes INTEGER,
                    duration_seconds INTEGER,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    device_serial TEXT,
                    device_model TEXT,
                    recording_mode TEXT,
                    recording_source_id INTEGER REFERENCES recording_sources(id) ON DELETE SET NULL,
                    sync_status TEXT NOT NULL DEFAULT 'local_only'
                )
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_recordings_filename_source
                    ON recordings(filename, recording_source_id)
                """)
            try db.execute(sql: "CREATE INDEX idx_recordings_source ON recordings(recording_source_id)")
            try db.execute(sql: "CREATE INDEX idx_recordings_source_created ON recordings(recording_source_id, created_at DESC)")

            // -- sources --
            try db.execute(sql: """
                CREATE TABLE sources (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                    source_type TEXT NOT NULL DEFAULT 'recording',
                    recording_id INTEGER REFERENCES recordings(id) ON DELETE SET NULL,
                    disk_path TEXT NOT NULL,
                    display_name TEXT,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    audio_path TEXT
                )
                """)

            // -- transcripts --
            try db.execute(sql: """
                CREATE TABLE transcripts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                    document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
                    title TEXT,
                    full_text TEXT,
                    md_file_path TEXT,
                    is_primary INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL DEFAULT 'ready',
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: """
                CREATE INDEX idx_transcripts_document_id
                    ON transcripts(document_id) WHERE document_id IS NOT NULL
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_transcripts_document_primary
                    ON transcripts(document_id) WHERE is_primary = 1 AND document_id IS NOT NULL
                """)

            // -- deletion_log --
            try db.execute(sql: """
                CREATE TABLE deletion_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    document_id INTEGER NOT NULL,
                    document_title TEXT,
                    folder_path TEXT,
                    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    trash_path TEXT NOT NULL,
                    expires_at DATETIME NOT NULL,
                    original_created_at DATETIME,
                    original_modified_at DATETIME
                )
                """)

            // -- token caches --
            try db.execute(sql: """
                CREATE TABLE document_token_cache (
                    document_id INTEGER PRIMARY KEY REFERENCES documents(id) ON DELETE CASCADE,
                    body_bytes INTEGER NOT NULL DEFAULT 0,
                    summary_bytes INTEGER NOT NULL DEFAULT 0,
                    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: """
                CREATE TABLE folder_token_cache (
                    folder_id INTEGER PRIMARY KEY REFERENCES folders(id) ON DELETE CASCADE,
                    total_bytes INTEGER NOT NULL DEFAULT 0,
                    document_count INTEGER NOT NULL DEFAULT 0,
                    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)

            // -- llm_accounts --
            try db.execute(sql: """
                CREATE TABLE llm_accounts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    provider TEXT NOT NULL,
                    email TEXT NOT NULL,
                    display_name TEXT NOT NULL DEFAULT '',
                    is_active INTEGER NOT NULL DEFAULT 1,
                    last_used_at DATETIME,
                    paused_until DATETIME,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: "CREATE UNIQUE INDEX idx_llm_accounts_provider_email ON llm_accounts(provider, email)")

            // -- api_logs --
            try db.execute(sql: """
                CREATE TABLE api_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    provider TEXT NOT NULL,
                    llm_account_id INTEGER REFERENCES llm_accounts(id) ON DELETE SET NULL,
                    model TEXT NOT NULL,
                    request_payload TEXT,
                    response_payload TEXT,
                    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    document_id INTEGER REFERENCES documents(id) ON DELETE SET NULL,
                    source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL,
                    transcript_id INTEGER REFERENCES transcripts(id) ON DELETE SET NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    error TEXT,
                    input_tokens INTEGER,
                    output_tokens INTEGER,
                    duration_ms INTEGER
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_api_logs_timestamp ON api_logs(timestamp)")
            try db.execute(sql: "CREATE INDEX idx_api_logs_document ON api_logs(document_id)")
            try db.execute(sql: "CREATE INDEX idx_api_logs_transcript ON api_logs(transcript_id) WHERE transcript_id IS NOT NULL")

            // -- llm_models --
            try db.execute(sql: """
                CREATE TABLE llm_models (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    provider TEXT NOT NULL,
                    model_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    supports_text INTEGER NOT NULL DEFAULT 1,
                    supports_audio INTEGER NOT NULL DEFAULT 0,
                    supports_image INTEGER NOT NULL DEFAULT 0,
                    max_input_tokens INTEGER,
                    max_output_tokens INTEGER,
                    daily_request_limit INTEGER,
                    tokens_per_minute INTEGER,
                    first_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(provider, model_id)
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_llm_models_provider ON llm_models(provider)")

            // -- llm_account_models --
            try db.execute(sql: """
                CREATE TABLE llm_account_models (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_id INTEGER NOT NULL REFERENCES llm_accounts(id) ON DELETE CASCADE,
                    model_id INTEGER NOT NULL REFERENCES llm_models(id) ON DELETE CASCADE,
                    is_available INTEGER NOT NULL DEFAULT 1,
                    last_checked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(account_id, model_id)
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_llm_account_models_model ON llm_account_models(model_id)")
            try db.execute(sql: "CREATE INDEX idx_llm_account_models_account ON llm_account_models(account_id)")

            // -- llm_usage --
            try db.execute(sql: """
                CREATE TABLE llm_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    account_id INTEGER NOT NULL REFERENCES llm_accounts(id) ON DELETE CASCADE,
                    model_id TEXT NOT NULL,
                    remaining_fraction REAL,
                    reset_at DATETIME,
                    last_checked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    input_tokens_used INTEGER NOT NULL DEFAULT 0,
                    output_tokens_used INTEGER NOT NULL DEFAULT 0,
                    request_count INTEGER NOT NULL DEFAULT 0,
                    period_start DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(account_id, model_id)
                )
                """)

            // -- llm_jobs --
            try db.execute(sql: """
                CREATE TABLE llm_jobs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    job_type TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending',
                    priority INTEGER NOT NULL DEFAULT 0,
                    provider TEXT NOT NULL,
                    model TEXT NOT NULL,
                    account_id INTEGER REFERENCES llm_accounts(id) ON DELETE SET NULL,
                    payload TEXT NOT NULL,
                    result_ref TEXT,
                    error_message TEXT,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    max_attempts INTEGER NOT NULL DEFAULT 3,
                    next_retry_at DATETIME,
                    document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
                    source_id INTEGER REFERENCES sources(id) ON DELETE CASCADE,
                    transcript_id INTEGER REFERENCES transcripts(id) ON DELETE SET NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    started_at DATETIME,
                    completed_at DATETIME
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_llm_jobs_status ON llm_jobs(status, priority DESC, created_at ASC)")
            try db.execute(sql: "CREATE INDEX idx_llm_jobs_document ON llm_jobs(document_id) WHERE document_id IS NOT NULL")

            AppLogger.database.info("Migration v1_initial complete")
        }

        return migrator
    }
    
    /// Close the database connection pool.
    func close() throws {
        try dbPool.close()
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

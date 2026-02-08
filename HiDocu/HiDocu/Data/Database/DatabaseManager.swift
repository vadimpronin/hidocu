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
            
            // transcriptions table (1:N with recordings, up to 5 variants)
            try db.execute(sql: """
                CREATE TABLE transcriptions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    recording_id INTEGER NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
                    full_text TEXT,
                    language TEXT,
                    model_used TEXT,
                    transcribed_at DATETIME,
                    confidence_score REAL,
                    title TEXT,
                    is_primary INTEGER NOT NULL DEFAULT 0
                )
                """)
            try db.execute(sql: """
                CREATE INDEX idx_transcriptions_recording_id ON transcriptions(recording_id)
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_transcriptions_single_primary
                    ON transcriptions(recording_id) WHERE is_primary = 1
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

        // v2: Context management system tables
        migrator.registerMigration("v2_context_management") { db in
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
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)

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
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)

            try db.execute(sql: """
                CREATE TABLE recordings_v2 (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    filename TEXT UNIQUE NOT NULL,
                    filepath TEXT NOT NULL,
                    title TEXT,
                    file_size_bytes INTEGER,
                    duration_seconds INTEGER,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    device_serial TEXT,
                    device_model TEXT,
                    recording_mode TEXT
                )
                """)

            try db.execute(sql: """
                CREATE TABLE sources (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                    source_type TEXT NOT NULL DEFAULT 'recording',
                    recording_id INTEGER REFERENCES recordings_v2(id) ON DELETE SET NULL,
                    disk_path TEXT NOT NULL,
                    display_name TEXT,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)

            try db.execute(sql: """
                CREATE TABLE transcripts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                    title TEXT,
                    full_text TEXT,
                    md_file_path TEXT,
                    is_primary INTEGER NOT NULL DEFAULT 0,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_transcripts_single_primary
                    ON transcripts(source_id) WHERE is_primary = 1
                """)

            try db.execute(sql: """
                CREATE TABLE deletion_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    document_id INTEGER NOT NULL,
                    document_title TEXT,
                    folder_path TEXT,
                    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    trash_path TEXT NOT NULL,
                    expires_at DATETIME NOT NULL
                )
                """)

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

            AppLogger.database.info("Migration v2_context_management complete")
        }

        // v3: Drop old tables, rename recordings_v2 → recordings
        migrator.registerMigration("v3_cleanup") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS segments")
            try db.execute(sql: "DROP TABLE IF EXISTS transcriptions")
            try db.execute(sql: "DROP TABLE IF EXISTS api_logs")
            try db.execute(sql: "DROP TABLE IF EXISTS settings")
            try db.execute(sql: "DROP TABLE IF EXISTS recordings")
            try db.execute(sql: "ALTER TABLE recordings_v2 RENAME TO recordings")

            AppLogger.database.info("Migration v3_cleanup complete")
        }

        // v4: Recreate sources table with correct FK (recordings_v2 → recordings)
        migrator.registerMigration("v4_fix_sources_fk") { db in
            // Disable FK checks during table rebuild
            try db.execute(sql: "PRAGMA foreign_keys = OFF")

            try db.execute(sql: """
                CREATE TABLE sources_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                    source_type TEXT NOT NULL DEFAULT 'recording',
                    recording_id INTEGER REFERENCES recordings(id) ON DELETE SET NULL,
                    disk_path TEXT NOT NULL,
                    display_name TEXT,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: """
                INSERT INTO sources_new (id, document_id, source_type, recording_id, disk_path, display_name, sort_order, added_at)
                SELECT id, document_id, source_type, recording_id, disk_path, display_name, sort_order, added_at
                FROM sources
                """)
            try db.execute(sql: "DROP TABLE sources")
            try db.execute(sql: "ALTER TABLE sources_new RENAME TO sources")

            try db.execute(sql: "PRAGMA foreign_keys = ON")

            AppLogger.database.info("Migration v4_fix_sources_fk complete")
        }

        // v5: Add original timestamps to deletion_log for proper restore
        migrator.registerMigration("v5_deletion_log_timestamps") { db in
            try db.execute(sql: "ALTER TABLE deletion_log ADD COLUMN original_created_at DATETIME")
            try db.execute(sql: "ALTER TABLE deletion_log ADD COLUMN original_modified_at DATETIME")
            AppLogger.database.info("Migration v5_deletion_log_timestamps complete")
        }

        // v6: Add disk_path to folders for hierarchical path tracking
        migrator.registerMigration("v6_hierarchical_paths") { db in
            try db.execute(sql: "ALTER TABLE folders ADD COLUMN disk_path TEXT")
            AppLogger.database.info("Migration v6_hierarchical_paths complete")
        }

        // v7: Add sort_order to documents for manual sorting
        migrator.registerMigration("v7_document_sort_order") { db in
            try db.execute(sql: "ALTER TABLE documents ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0")

            // Backfill documents: oldest first within each folder
            try db.execute(sql: """
                UPDATE documents SET sort_order = (
                    SELECT cnt - 1 FROM (
                        SELECT id, ROW_NUMBER() OVER (
                            PARTITION BY folder_id ORDER BY created_at ASC
                        ) AS cnt FROM documents
                    ) AS ranked WHERE ranked.id = documents.id
                )
                """)

            // Backfill folders: oldest first within each parent
            try db.execute(sql: """
                UPDATE folders SET sort_order = (
                    SELECT cnt - 1 FROM (
                        SELECT id, ROW_NUMBER() OVER (
                            PARTITION BY parent_id ORDER BY created_at ASC
                        ) AS cnt FROM folders
                    ) AS ranked WHERE ranked.id = folders.id
                )
                """)

            // Index for efficient sort queries
            try db.execute(sql: "CREATE INDEX idx_documents_folder_sort ON documents(folder_id, sort_order)")

            AppLogger.database.info("Migration v7_document_sort_order complete")
        }

        // v8: LLM integration tables
        migrator.registerMigration("v8_llm_integration") { db in
            try db.execute(sql: """
                CREATE TABLE llm_accounts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    provider TEXT NOT NULL,
                    email TEXT NOT NULL,
                    display_name TEXT NOT NULL DEFAULT '',
                    is_active INTEGER NOT NULL DEFAULT 1,
                    last_used_at DATETIME,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                )
                """)
            try db.execute(sql: "CREATE UNIQUE INDEX idx_llm_accounts_provider_email ON llm_accounts(provider, email)")

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
                    status TEXT NOT NULL DEFAULT 'pending',
                    error TEXT,
                    input_tokens INTEGER,
                    output_tokens INTEGER,
                    duration_ms INTEGER
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_api_logs_timestamp ON api_logs(timestamp)")
            try db.execute(sql: "CREATE INDEX idx_api_logs_document ON api_logs(document_id)")

            AppLogger.database.info("Migration v8_llm_integration complete")
        }

        // v9: Summary metadata fields
        migrator.registerMigration("v9_summary_metadata") { db in
            try db.execute(sql: "ALTER TABLE documents ADD COLUMN summary_generated_at DATETIME")
            try db.execute(sql: "ALTER TABLE documents ADD COLUMN summary_model TEXT")
            try db.execute(sql: "ALTER TABLE documents ADD COLUMN summary_edited INTEGER NOT NULL DEFAULT 0")

            AppLogger.database.info("Migration v9_summary_metadata complete")
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

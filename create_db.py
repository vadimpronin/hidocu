#!/usr/bin/env python3
"""
Create HiDocu database structure if it doesn't exist.
This script initializes the database with all required tables.
"""

import sqlite3
from pathlib import Path


def create_database(db_path: str):
    """Create HiDocu database with all tables"""

    # Ensure parent directory exists
    db_file = Path(db_path)
    db_file.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")

    cursor = conn.cursor()

    # Create folders table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            disk_path TEXT,
            transcription_context TEXT,
            categorization_context TEXT,
            prefer_summary INTEGER NOT NULL DEFAULT 1,
            minimize_before_llm INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            modified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # Create documents table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS documents (
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

    # Create recordings table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS recordings (
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

    # Create sources table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS sources (
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

    # Create transcripts table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS transcripts (
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

    cursor.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_transcripts_single_primary
            ON transcripts(source_id) WHERE is_primary = 1
    """)

    # Create deletion_log table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS deletion_log (
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

    # Create token cache tables
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS document_token_cache (
            document_id INTEGER PRIMARY KEY REFERENCES documents(id) ON DELETE CASCADE,
            body_bytes INTEGER NOT NULL DEFAULT 0,
            summary_bytes INTEGER NOT NULL DEFAULT 0,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS folder_token_cache (
            folder_id INTEGER PRIMARY KEY REFERENCES folders(id) ON DELETE CASCADE,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            document_count INTEGER NOT NULL DEFAULT 0,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # Create migrations table to track schema version
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS grdb_migrations (
            identifier TEXT PRIMARY KEY NOT NULL
        )
    """)

    # Mark migrations as applied
    migrations = [
        'v1_initial',
        'v2_context_management',
        'v3_cleanup',
        'v4_fix_sources_fk',
        'v5_deletion_log_timestamps',
        'v6_hierarchical_paths'
    ]

    for migration in migrations:
        cursor.execute("INSERT OR IGNORE INTO grdb_migrations (identifier) VALUES (?)", (migration,))

    conn.commit()
    conn.close()

    print(f"✓ Database created at: {db_path}")


if __name__ == '__main__':
    import sys

    # Default database path
    home = Path.home()
    db_path = home / "Library" / "Application Support" / "HiDocu" / "hidocu.sqlite"

    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])

    print(f"Creating HiDocu database at: {db_path}")
    create_database(str(db_path))
    print("✓ Database ready for import!")

#!/usr/bin/env python3
"""
HiDocu Data Import Script

Imports markdown files from a directory structure into HiDocu's database and file system.
Maps directory structure to folders and files to documents.

Usage:
    python import_data.py [--source-dir PATH] [--db-path PATH] [--data-dir PATH]

Directory structure assumptions:
- Top-level directory becomes root folder
- Subdirectories become nested folders
- .md files become documents
- File numbering prefixes (00_, 01_, etc.) are stripped from titles
- Files are sorted by name for consistent ordering
"""

import sqlite3
import os
import sys
import shutil
import argparse
from pathlib import Path
from datetime import datetime, timedelta
import hashlib


class HiDocuImporter:
    def __init__(self, db_path: str, data_dir: str):
        self.db_path = db_path
        self.data_dir = Path(data_dir)
        self.conn = None
        self.folder_map = {}  # path -> folder_id mapping

    def connect(self):
        """Connect to the SQLite database"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute("PRAGMA foreign_keys = ON")

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()

    def clean_title(self, filename: str) -> str:
        """
        Clean up filename to create a nice title.
        Removes .md extension and common prefixes.
        """
        # Remove extension
        name = filename.replace('.md', '')

        # Remove numeric prefixes like "00_", "01_", "1_", "2_", etc.
        parts = name.split('_', 1)
        if len(parts) > 1 and parts[0].isdigit():
            name = parts[1]

        # Replace underscores with spaces
        name = name.replace('_', ' ')

        # Capitalize words
        name = ' '.join(word.capitalize() for word in name.split())

        return name

    def create_folder(self, name: str, parent_id: int = None) -> int:
        """Create a folder in the database"""
        now = datetime.now().isoformat()
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO folders (parent_id, name, transcription_context, categorization_context,
                               prefer_summary, minimize_before_llm, sort_order, created_at, modified_at)
            VALUES (?, ?, '', '', 1, 0, 0, ?, ?)
        """, (parent_id, name, now, now))
        folder_id = cursor.lastrowid
        self.conn.commit()
        print(f"  Created folder: {name} (id={folder_id}, parent={parent_id})")
        return folder_id

    def get_or_create_folder_hierarchy(self, rel_path: Path) -> int:
        """
        Get or create folder hierarchy for a path.
        Returns the folder_id for the deepest folder.
        """
        # Root level - no folder
        if rel_path == Path('.'):
            return None

        parts = rel_path.parts
        parent_id = None

        for i, part in enumerate(parts):
            current_path = Path(*parts[:i+1])
            path_str = str(current_path)

            if path_str not in self.folder_map:
                folder_id = self.create_folder(part, parent_id)
                self.folder_map[path_str] = folder_id
            else:
                folder_id = self.folder_map[path_str]

            parent_id = folder_id

        return parent_id

    def sha256(self, content: str) -> str:
        """Calculate SHA256 hash of content"""
        return hashlib.sha256(content.encode('utf-8')).hexdigest()

    def create_document(self, title: str, folder_id: int, content: str, created_at: datetime) -> int:
        """Create a document in the database and file system"""
        now = datetime.now().isoformat()
        created_iso = created_at.isoformat()

        # Insert placeholder to get ID
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO documents (folder_id, title, document_type, disk_path, body_preview,
                                 summary_text, body_hash, summary_hash, prefer_summary,
                                 minimize_before_llm, created_at, modified_at)
            VALUES (?, ?, 'markdown', 'pending', ?, '', ?, '', 0, 0, ?, ?)
        """, (folder_id, title, content[:500], self.sha256(content), created_iso, created_iso))
        doc_id = cursor.lastrowid

        # Create document folder structure
        disk_path = f"{doc_id}.document"
        doc_folder = self.data_dir / disk_path
        doc_folder.mkdir(parents=True, exist_ok=True)
        (doc_folder / "sources").mkdir(exist_ok=True)

        # Write body.md
        body_file = doc_folder / "body.md"
        body_file.write_text(content, encoding='utf-8')

        # Write empty summary.md
        summary_file = doc_folder / "summary.md"
        summary_file.write_text('', encoding='utf-8')

        # Write metadata.yaml
        metadata_content = f"""title: {title}
created: {created_iso}
modified: {created_iso}
"""
        metadata_file = doc_folder / "metadata.yaml"
        metadata_file.write_text(metadata_content, encoding='utf-8')

        # Update document with real disk path
        cursor.execute("""
            UPDATE documents
            SET disk_path = ?
            WHERE id = ?
        """, (disk_path, doc_id))
        self.conn.commit()

        print(f"    Created document: {title} (id={doc_id})")
        return doc_id

    def import_directory(self, source_dir: Path):
        """Import all markdown files from source directory"""
        source_dir = Path(source_dir)

        if not source_dir.exists():
            raise FileNotFoundError(f"Source directory not found: {source_dir}")

        # Ensure data directory exists
        self.data_dir.mkdir(parents=True, exist_ok=True)

        # Find all .md files
        md_files = sorted(source_dir.rglob("*.md"))

        if not md_files:
            print(f"No .md files found in {source_dir}")
            return

        print(f"\nFound {len(md_files)} markdown files to import\n")

        # Process each file
        for i, md_file in enumerate(md_files):
            # Calculate relative path from source directory
            rel_path = md_file.relative_to(source_dir)
            folder_path = rel_path.parent

            # Get or create folder hierarchy
            folder_id = self.get_or_create_folder_hierarchy(folder_path)

            # Read content
            try:
                content = md_file.read_text(encoding='utf-8')
            except Exception as e:
                print(f"    ERROR reading {md_file}: {e}")
                continue

            # Create document
            title = self.clean_title(md_file.name)

            # Use file modification time as creation date, offset by index to maintain order
            file_mtime = datetime.fromtimestamp(md_file.stat().st_mtime)
            # Subtract index * 1 minute to ensure files sort correctly by creation date
            created_at = file_mtime - timedelta(minutes=len(md_files) - i)

            self.create_document(title, folder_id, content, created_at)

        print(f"\n✓ Import complete! Imported {len(md_files)} documents")

    def clear_database(self):
        """Clear all folders and documents from database"""
        print("\nClearing existing data...")
        cursor = self.conn.cursor()
        cursor.execute("DELETE FROM transcripts")
        cursor.execute("DELETE FROM sources")
        cursor.execute("DELETE FROM documents")
        cursor.execute("DELETE FROM folders")
        cursor.execute("DELETE FROM deletion_log")
        self.conn.commit()
        print("✓ Database cleared")

    def clear_filesystem(self):
        """Remove all document folders from file system"""
        if self.data_dir.exists():
            print(f"Clearing file system at {self.data_dir}...")
            for item in self.data_dir.iterdir():
                if item.is_dir() and item.name.endswith('.document'):
                    shutil.rmtree(item)
            print("✓ File system cleared")


def find_db_path():
    """Try to find the HiDocu database automatically"""
    home = Path.home()

    # Check sandboxed container (macOS app with sandbox enabled)
    sandboxed = home / "Library" / "Containers" / "com.hidocu.app" / "Data" / "Library" / "Application Support" / "HiDocu" / "hidocu.sqlite"
    if sandboxed.exists():
        return str(sandboxed)

    # Check Application Support (non-sandboxed)
    app_support = home / "Library" / "Application Support" / "HiDocu" / "hidocu.sqlite"
    if app_support.exists():
        return str(app_support)

    # Fallback to .db extension
    app_support_db = home / "Library" / "Application Support" / "HiDocu" / "hidocu.db"
    if app_support_db.exists():
        return str(app_support_db)

    # Check home directory
    home_db = home / "HiDocu" / "hidocu.sqlite"
    if home_db.exists():
        return str(home_db)

    return None


def find_data_dir():
    """Find the HiDocu data directory"""
    home = Path.home()

    # Check sandboxed container (macOS app with sandbox enabled)
    sandboxed = home / "Library" / "Containers" / "com.hidocu.app" / "Data" / "HiDocu"
    if sandboxed.exists():
        return str(sandboxed)

    # Default location
    default_dir = home / "HiDocu"
    return str(default_dir)


def main():
    parser = argparse.ArgumentParser(
        description="Import markdown files into HiDocu database and file system"
    )
    parser.add_argument(
        '--source-dir',
        default='data/Job Interviews',
        help='Source directory containing .md files (default: data/Job Interviews)'
    )
    parser.add_argument(
        '--db-path',
        help='Path to HiDocu database (default: auto-detect)'
    )
    parser.add_argument(
        '--data-dir',
        help='Path to HiDocu data directory (default: ~/HiDocu)'
    )
    parser.add_argument(
        '--clear',
        action='store_true',
        help='Clear existing data before importing'
    )
    parser.add_argument(
        '--yes', '-y',
        action='store_true',
        help='Skip confirmation prompts'
    )

    args = parser.parse_args()

    # Resolve paths
    db_path = args.db_path or find_db_path()
    data_dir = args.data_dir or find_data_dir()

    if not db_path:
        print("ERROR: Could not find HiDocu database.")
        print("Please specify --db-path or run the HiDocu app first to create the database.")
        sys.exit(1)

    print("HiDocu Data Importer")
    print("=" * 60)
    print(f"Database:   {db_path}")
    print(f"Data dir:   {data_dir}")
    print(f"Source:     {args.source_dir}")
    print("=" * 60)

    if not Path(db_path).exists():
        print(f"\nERROR: Database not found at {db_path}")
        print("Please run the HiDocu app first to create the database.")
        sys.exit(1)

    # Create importer
    importer = HiDocuImporter(db_path, data_dir)

    try:
        importer.connect()

        if args.clear:
            if not args.yes:
                response = input("\n⚠️  This will DELETE all existing folders and documents. Continue? (yes/no): ")
                if response.lower() != 'yes':
                    print("Aborted.")
                    sys.exit(0)
            importer.clear_database()
            importer.clear_filesystem()

        # Import
        importer.import_directory(args.source_dir)

    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        importer.close()

    print("\n✓ All done! Launch HiDocu to see your data.")


if __name__ == '__main__':
    main()

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
import re


def sanitize_filename(name):
    """Sanitize a string for use as a file/directory name (matches Swift PathSanitizer)."""
    # Replace path traversal
    result = name.replace('..', '_')
    # Replace / : null and control chars
    result = re.sub(r'[/:\x00-\x1f]', '-', result)
    # Collapse multiple spaces
    result = re.sub(r' +', ' ', result)
    # Trim whitespace and dots
    result = result.strip().strip('.')
    # Truncate to 255 bytes
    while len(result.encode('utf-8')) > 255:
        result = result[:-1]
    # Fallback
    if not result:
        result = 'Untitled'
    return result


class HiDocuImporter:
    def __init__(self, db_path: str, data_dir: str, db_only: bool = False):
        self.db_path = db_path
        self.data_dir = Path(data_dir)
        self.conn = None
        self.folder_map = {}  # path -> (folder_id, disk_path) mapping
        self.db_only = db_only  # skip file creation, reuse existing files on disk

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

    def create_folder(self, name: str, parent_id: int = None, parent_disk_path: str = "") -> tuple:
        """Create a folder in the database and file system. Returns (folder_id, disk_path)."""
        now = datetime.now().isoformat()
        sanitized = sanitize_filename(name)
        disk_path = f"{parent_disk_path}/{sanitized}" if parent_disk_path else sanitized

        if not self.db_only:
            folder_dir = self.data_dir / disk_path
            folder_dir.mkdir(parents=True, exist_ok=True)

        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO folders (parent_id, name, disk_path, transcription_context, categorization_context,
                               prefer_summary, minimize_before_llm, sort_order, created_at, modified_at)
            VALUES (?, ?, ?, '', '', 1, 0, 0, ?, ?)
        """, (parent_id, name, disk_path, now, now))
        folder_id = cursor.lastrowid
        self.conn.commit()
        print(f"  Created folder: {name} (id={folder_id}, path={disk_path})")
        return (folder_id, disk_path)

    def get_or_create_folder_hierarchy(self, rel_path: Path) -> tuple:
        """
        Get or create folder hierarchy for a path.
        Returns (folder_id, disk_path) for the deepest folder.
        """
        # Root level - no folder
        if rel_path == Path('.'):
            return (None, "")

        parts = rel_path.parts
        parent_id = None
        parent_disk_path = ""

        for i, part in enumerate(parts):
            current_path = Path(*parts[:i+1])
            path_str = str(current_path)

            if path_str not in self.folder_map:
                folder_id, disk_path = self.create_folder(part, parent_id, parent_disk_path)
                self.folder_map[path_str] = (folder_id, disk_path)
            else:
                folder_id, disk_path = self.folder_map[path_str]

            parent_id = folder_id
            parent_disk_path = disk_path

        return (parent_id, parent_disk_path)

    def sha256(self, content: str) -> str:
        """Calculate SHA256 hash of content"""
        return hashlib.sha256(content.encode('utf-8')).hexdigest()

    def create_document(self, title: str, folder_id: int, content: str, created_at: datetime, folder_disk_path: str = "") -> int:
        """Create a document in the database and file system"""
        now = datetime.now().isoformat()
        created_iso = created_at.isoformat()

        # Sanitize title for filesystem
        sanitized = sanitize_filename(title)
        doc_dir_name = f"{sanitized}.document"
        disk_path = f"{folder_disk_path}/{doc_dir_name}" if folder_disk_path else doc_dir_name

        if not self.db_only:
            # Handle conflicts (only when creating files)
            counter = 2
            while (self.data_dir / disk_path).exists():
                doc_dir_name = f"{sanitized} {counter}.document"
                disk_path = f"{folder_disk_path}/{doc_dir_name}" if folder_disk_path else doc_dir_name
                counter += 1

        # Insert with real disk path directly (no placeholder)
        cursor = self.conn.cursor()
        cursor.execute("""
            INSERT INTO documents (folder_id, title, document_type, disk_path, body_preview,
                                 summary_text, body_hash, summary_hash, prefer_summary,
                                 minimize_before_llm, created_at, modified_at)
            VALUES (?, ?, 'markdown', ?, ?, '', ?, '', 0, 0, ?, ?)
        """, (folder_id, title, disk_path, content[:500], self.sha256(content), created_iso, created_iso))
        doc_id = cursor.lastrowid

        if not self.db_only:
            # Create document folder
            doc_folder = self.data_dir / disk_path
            doc_folder.mkdir(parents=True, exist_ok=True)
            (doc_folder / "sources").mkdir(exist_ok=True)

            # Write files
            (doc_folder / "body.md").write_text(content, encoding='utf-8')
            (doc_folder / "summary.md").write_text('', encoding='utf-8')

        # Write metadata.yaml (always — updates doc id for this DB)
        doc_folder = self.data_dir / disk_path
        escaped_title = title.replace('"', '\\"')
        metadata_content = f'id: {doc_id}\ntitle: "{escaped_title}"\ncreated: {created_iso}\n'
        (doc_folder / "metadata.yaml").write_text(metadata_content, encoding='utf-8')

        self.conn.commit()
        print(f"    Created document: {title} (id={doc_id}, path={disk_path})")
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
            folder_id, folder_disk_path = self.get_or_create_folder_hierarchy(folder_path)

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

            self.create_document(title, folder_id, content, created_at, folder_disk_path)

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
        """Remove all document folders and physical folders from file system"""
        if self.data_dir.exists():
            print(f"Clearing file system at {self.data_dir}...")
            for item in self.data_dir.iterdir():
                if item.is_dir() and not item.name.startswith('.'):
                    shutil.rmtree(item)
            print("✓ File system cleared")


DB_LOCATIONS = [
    ("Application Support", "Library/Application Support/HiDocu/hidocu.sqlite"),
    ("Sandbox container", "Library/Containers/com.hidocu.app/Data/Library/Application Support/HiDocu/hidocu.sqlite"),
    ("Application Support (.db)", "Library/Application Support/HiDocu/hidocu.db"),
    ("Home directory", "HiDocu/hidocu.sqlite"),
]


def find_all_db_paths():
    """Find all existing HiDocu database instances."""
    home = Path.home()
    found = []
    for label, rel_path in DB_LOCATIONS:
        full = home / rel_path
        if full.exists():
            found.append((label, str(full)))
    return found


def choose_db_paths(found, auto_yes=False):
    """
    Let the user choose which databases to update.
    Returns a list of (label, path) tuples.
    If --yes is set or only one DB exists, skips the prompt.
    """
    if len(found) == 1:
        return found

    print(f"\nFound {len(found)} database instances:")
    for i, (label, path) in enumerate(found, 1):
        print(f"  {i}) [{label}] {path}")
    print(f"  a) All of the above")

    if auto_yes:
        print("  -> --yes flag set, updating all.\n")
        return found

    while True:
        choice = input("\nWhich database(s) to update? [a]: ").strip().lower() or "a"
        if choice == "a":
            return found
        if choice.isdigit() and 1 <= int(choice) <= len(found):
            return [found[int(choice) - 1]]
        # Support comma-separated like "1,2"
        parts = [p.strip() for p in choice.split(",")]
        if all(p.isdigit() and 1 <= int(p) <= len(found) for p in parts):
            return [found[int(p) - 1] for p in parts]
        print("Invalid choice. Enter a number, comma-separated numbers, or 'a' for all.")


def find_data_dir():
    """Find the HiDocu data directory"""
    home = Path.home()

    # Default location (used by non-sandboxed builds)
    default_dir = home / "HiDocu"
    return str(default_dir)


def main():
    parser = argparse.ArgumentParser(
        description="Import markdown files into HiDocu database and file system"
    )
    parser.add_argument(
        '--source-dir',
        default='tmp/Job Interviews',
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

    data_dir = args.data_dir or find_data_dir()

    # Resolve database target(s)
    if args.db_path:
        # Explicit path — single target
        db_targets = [("user-specified", args.db_path)]
        if not Path(args.db_path).exists():
            print(f"ERROR: Database not found at {args.db_path}")
            sys.exit(1)
    else:
        found = find_all_db_paths()
        if not found:
            print("ERROR: Could not find any HiDocu database.")
            print("Please specify --db-path or run the HiDocu app first to create the database.")
            sys.exit(1)
        db_targets = choose_db_paths(found, auto_yes=args.yes)

    print("HiDocu Data Importer")
    print("=" * 60)
    for label, path in db_targets:
        print(f"Database:   {path}  [{label}]")
    print(f"Data dir:   {data_dir}")
    print(f"Source:     {args.source_dir}")
    print("=" * 60)

    if args.clear and not args.yes:
        response = input("\n⚠️  This will DELETE all existing folders and documents. Continue? (yes/no): ")
        if response.lower() != 'yes':
            print("Aborted.")
            sys.exit(0)

    filesystem_cleared = False
    files_created = False

    for label, db_path in db_targets:
        print(f"\n{'─' * 60}")
        print(f"Importing into: {db_path}  [{label}]")
        print(f"{'─' * 60}")

        # After the first import creates files, subsequent imports only update the DB
        importer = HiDocuImporter(db_path, data_dir, db_only=files_created)
        try:
            importer.connect()

            if args.clear:
                importer.clear_database()
                if not filesystem_cleared:
                    importer.clear_filesystem()
                    filesystem_cleared = True

            importer.import_directory(args.source_dir)
            files_created = True
        except Exception as e:
            print(f"\n❌ ERROR importing into {db_path}: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)
        finally:
            importer.close()

    print("\n✓ All done! Launch HiDocu to see your data.")


if __name__ == '__main__':
    main()

# HiDocu Data Import Guide

This guide explains how to import markdown files from a directory structure into HiDocu.

## Quick Start

1. **Run HiDocu app once** to create the database (just launch and quit)

2. **Run the import script:**
   ```bash
   python3 import_data.py
   ```

That's it! The script will:
- Auto-detect the HiDocu database location
- Import from `data/Job Interviews/` by default
- Create folders matching your directory structure
- Import all `.md` files as documents

## How It Works

### Directory → Folder Mapping
- Each directory becomes a folder in HiDocu
- Nested directories become nested folders
- Example:
  ```
  data/Job Interviews/ThriveCart/  → Folder: "Job Interviews" > "ThriveCart"
  data/Job Interviews/Amplemarket/ → Folder: "Job Interviews" > "Amplemarket"
  ```

### File → Document Mapping
- Each `.md` file becomes a document
- File content becomes the document body
- Filename becomes the document title (cleaned up)
- Numeric prefixes are stripped: `00_jd.md` → "Jd"

### Timestamps
- Files are ordered by filename (alphabetically)
- Creation dates are assigned to maintain sort order
- Older-named files get earlier dates

## Advanced Usage

### Custom Source Directory
```bash
python3 import_data.py --source-dir /path/to/your/markdown/files
```

### Custom Database Location
```bash
python3 import_data.py --db-path /path/to/hidocu.db
```

### Custom Data Directory
```bash
python3 import_data.py --data-dir /path/to/HiDocu/data
```

### Clear Existing Data
⚠️ **Warning:** This deletes ALL folders and documents!

```bash
python3 import_data.py --clear
```

### Full Example
```bash
python3 import_data.py \
  --source-dir ~/Documents/interviews \
  --db-path ~/Library/Application\ Support/HiDocu/hidocu.db \
  --data-dir ~/HiDocu \
  --clear
```

## Database Location

The script auto-detects the database in these locations (checked in order):
1. `~/Library/Containers/com.hidocu.app/Data/Library/Application Support/HiDocu/hidocu.sqlite` (sandboxed macOS app - **primary**)
2. `~/Library/Application Support/HiDocu/hidocu.sqlite` (non-sandboxed)
3. `~/HiDocu/hidocu.sqlite` (fallback)

**Note:** Xcode builds use sandboxing, so the database will be in the Containers directory.

## Data Directory

The script auto-detects the data directory:
1. `~/Library/Containers/com.hidocu.app/Data/HiDocu/` (sandboxed - **primary**)
2. `~/HiDocu/` (non-sandboxed fallback)

Each document gets a folder like `123.document/` containing:
- `body.md` - Main content
- `summary.md` - Summary (empty after import)
- `metadata.yaml` - Title and timestamps
- `sources/` - Folder for sources (empty after import)

## Troubleshooting

### "Database not found"
Run HiDocu app once to create the database, then try again.

### "No .md files found"
Check that your source directory path is correct and contains `.md` files.

### Permission errors
The script needs read access to your markdown files and write access to `~/HiDocu/`.

### Import duplicates
Use `--clear` to remove existing data before re-importing.

## Example: Your Job Interviews

Your current structure:
```
data/Job Interviews/
├── ThriveCart/
│   ├── 00_jd.md
│   ├── 01_cv.md
│   ├── 02_cover_letter.md
│   └── 3_head_of_payments_interview.md
├── Amplemarket/
│   └── interview2.md
├── SDG/
│   ├── 00_cv.md
│   └── 00_jd.md
└── ...
```

Will become:
```
Folders:
└── Job Interviews
    ├── ThriveCart
    ├── Amplemarket
    ├── SDG
    └── ...

Documents in "ThriveCart":
- Jd
- Cv
- Cover Letter
- Head Of Payments Interview

Documents in "Amplemarket":
- Interview2
```

## Re-importing

To re-import with fresh data:

1. **Clear and re-import:**
   ```bash
   python3 import_data.py --clear
   ```

2. **Import from different source:**
   ```bash
   python3 import_data.py --source-dir ~/new-data --clear
   ```

## Dependencies

The script requires Python 3.7+ with:
- `sqlite3` (built-in)
- `yaml` (install: `pip3 install pyyaml`)

Install PyYAML if needed:
```bash
pip3 install pyyaml
```

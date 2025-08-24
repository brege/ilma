# ilma

A project-aware backup and archival tool that creates context mirrors with statistics for LLM consumption.

## Dependencies

### Required
- `rsync` - File synchronization (core backup functionality) 
- `zstd` - Compression
- `tree` - Project structure visualization
- `git` - Version control integration (gracefully handles non-git directories)
- `bc` - Command-line calculator

Debian/Ubuntu: 
``` bash
sudo apt install rsync tree git zstd bc
```
Fedora:
``` bash
sudo dnf install rsync tree git zstd bc
```

Most systems have these tools pre-installed. On minimal systems, you may need to install `tree` and `zstd`.

## Installation

1. Add `~/build/ilma` to your PATH
2. Add `.ilma.conf` to your global git excludes: `echo ".ilma.conf" >> ~/.config/git/ignore`
3. Create project-specific configuration files as needed

## Usage

```bash
# Backup current directory
ilma

# Backup specific project
ilma /path/to/project

# Show stats only (no backup)
ilma -c
ilma /path/to/project -c
```

## Default Configuration

By default, ilma uses minimal exclusions and tracks basic file types:

### Default Exclusions
- `.git/` - Git repository data
- `.gitignore` - Git ignore file
- `.archive.conf` - Legacy config file
- `.ilma.conf` - ilma config file
- `.backup.conf` - Alternative config file

### Default File Extensions Tracked
- `md` - Markdown files
- `txt` - Text files

### Default Backup Location
- `~/build/` - Working backups stored here
- No compressed archives by default
- No XDG directory backup by default

## Project Configuration

Create a `.ilma.conf` file in your project root to customize behavior:

```bash
# Example ABC configuration (Archive, Backup, Context)
EXTENSIONS=(js ts md json)
BACKUP_XDG_DIRS=true
BACKUP_BASE_DIR="../backup"
ARCHIVE_BASE_DIR="../archive"
CONTEXT_BASE_DIR="../context"
CREATE_COMPRESSED_ARCHIVE=true
MAX_ARCHIVES=3

RSYNC_EXCLUDES+=(
    --exclude 'node_modules/'
    --exclude 'dist/'
)

CONTEXT_FILES=(
    "docs/README.md"
    "CHANGELOG.md"
)

TREE_EXCLUDES+="|node_modules|dist"
```

## Configuration Options

### Backup Locations
- `BACKUP_BASE_DIR` - Where working backups are stored (default: `$HOME/build`)
- `ARCHIVE_BASE_DIR` - Where compressed archives are stored (empty = disabled)
- `CONTEXT_BASE_DIR` - Where context mirrors are stored (empty = nested in backup)
- `CREATE_COMPRESSED_ARCHIVE` - Create timestamped .tar.zst files (default: false)
- `MAX_ARCHIVES` - Number of compressed archives to keep (default: 1)

### XDG Directory Backup
- `BACKUP_XDG_DIRS` - Backup user config directories (default: false)  
- `XDG_PATHS` - Directories to check (default: `~/.config` `~/.local/share` `~/.cache`)

### File Tracking
- `EXTENSIONS` - File types to track in statistics
- `RSYNC_EXCLUDES` - Patterns to exclude from backup (use `+=` to extend defaults)
- `CONTEXT_FILES` - Additional files to copy to mirror root
- `TREE_EXCLUDES` - Patterns to exclude from tree output (use `+=` to extend)

## Example Configurations

### Node.js Project
```bash
# .ilma.conf
EXTENSIONS=(js ts md json yaml)
BACKUP_XDG_DIRS=false

RSYNC_EXCLUDES+=(
    --exclude 'node_modules/'
    --exclude 'package-lock.json'
    --exclude 'dist/'
    --exclude 'build/'
    --exclude '.next/'
    --exclude 'coverage/'
)

TREE_EXCLUDES+="|node_modules|dist|build"
```

### Python Project
```bash
# .ilma.conf
EXTENSIONS=(py md txt yaml json)
BACKUP_XDG_DIRS=false

RSYNC_EXCLUDES+=(
    --exclude '__pycache__/'
    --exclude '*.pyc'
    --exclude '*.pyo'
    --exclude '.pytest_cache/'
    --exclude 'venv/'
    --exclude '.venv/'
    --exclude 'env/'
    --exclude '.tox/'
    --exclude 'dist/'
    --exclude 'build/'
    --exclude '*.egg-info/'
)

TREE_EXCLUDES+="|__pycache__|venv|.venv|dist|build"
```

### LaTeX Project
```bash
# .ilma.conf
EXTENSIONS=(tex md txt bib)
BACKUP_XDG_DIRS=false

RSYNC_EXCLUDES+=(
    --exclude '*.aux'
    --exclude '*.log'
    --exclude '*.out'
    --exclude '*.toc'
    --exclude '*.lof'
    --exclude '*.lot'
    --exclude '*.fdb_latexmk'
    --exclude '*.fls'
    --exclude '*.synctex.gz'
    --exclude '*.bbl'
    --exclude '*.blg'
    --exclude '*.run.xml'
    --exclude '*.bcf'
    --exclude '_minted-*/'
)

CONTEXT_FILES=(
    "README.md"
    "*.pdf"
)

TREE_EXCLUDES+="|_minted-*"
```


## ABC Architecture

**`ilma`** implements an Archive-Backup-Context pattern:

### Default Structure (nested)
```
~/build/
├── project.bak/          # Full backup
│   ├── ...              # Complete 1:1 copy
│   └── project/         # Context mirror (LLM-ready)
└── project-timestamp.tar.zst  # Optional compressed archive
```

### Separated Structure (with CONTEXT_BASE_DIR)
```
../
├── archive/project-timestamp.tar.zst  # Compressed archives
├── backup/project.bak/                # Full backups  
└── context/project/                   # Context mirrors
```

## Output

**`ilma`** creates:
1. **Archive** - Optional compressed timestamped .tar.zst files with rotation
2. **Backup** - Complete 1:1 copy at `$BACKUP_BASE_DIR/project.bak/`
3. **Context** - LLM-ready mirror at `$CONTEXT_BASE_DIR/project/` or nested
4. **Statistics** - File counts, line counts, size reduction analysis
5. **Tree file** - Project structure snapshot in context mirror

## License

[GPLv3](https://www.gnu.org/licenses/gpl-3.0.txt)

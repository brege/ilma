# `ilma`

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

``` bash
git clone https://github.com/brege/ilma
cd ilma
```

1. Add `ilma` to your PATH
2. (Optional) Add `.ilma.conf` to your global git excludes: `echo ".ilma.conf" >> ~/.config/git/ignore`
3. Create project-specific configuration files as needed

## Usage

``` bash
# Backup current directory (default behavior)
ilma

# Backup specific project
ilma /path/to/project

# Show project statistics (no backup)
ilma console
ilma console /path/to/project

# Scan for junk files (all paths marked as artifacts)
ilma scan --type python --pretty

# Junk file pruning workflow
ilma prune --verbose                 # Preview what would be deleted
ilma prune --type latex --bak        # Backup then clean LaTeX project
ilma prune --type python --delete    # Delete junk files (no backup)

# Show configuration
ilma config
ilma config /path/to/project
```

### Commands

**`ilma [backup]`** - Create backup and context mirror (default command)
**`ilma console`**  - Show project statistics and analysis  
**`ilma scan`**     - Scan for junk files based on project type
**`ilma prune`**    - Analyze and optionally remove junk files
**`ilma config`**   - Display current configuration settings

Use `ilma COMMAND --help` for detailed help on each command.

### Console

**`ilma`** has a built-in statistics view that shows file counts, line counts, and size reduction analysis.

``` text
> ~/thunder-muscle$ ilma console

  Mirror Reduction Stats
  ----------------------
  Metric                 Source     Mirror      Delta Reduction
  -----                  ------     ------      ----- --------
  Total files              3249         50       3199    98.5%
  .py files                1260         10       1250    99.2%
  .md files                   5          3          2    40.0%
  .json files                16         12          4    25.0%
  Total lines           2182245    1453607     728638    33.4%
  .py lines              372962       1954     371008    99.5%
  .md lines                 482        254        228    47.3%
  .json lines           1444974    1444364        610     0.0%
  Total size (MB)           288        196         92    31.9%
  ----------------------
  Mirror token estimate: 51331435 (~4 chars per token)
  git: [ commits: 9 ][ latest: 2025-08-29:16:42 (64ebf25) docs: update README.md ]
  tip: ilma console (this display) | ilma --help
```
This overview is useful for quickly evaluating the impact your source code might have on an LLM's context window.

Using **`ilma`** from your project root will automatically create a minimal snapshot of your project in the same parent directory as the project itself. An `.ilma.conf` in the source root allows finer control over replaceable assets to duplicate.

## Default Configuration

By default, **`ilma`** uses minimal exclusions and tracks basic file types:

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
- Current directory (`.`) - Working backups stored here by default
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
- `BACKUP_BASE_DIR` - Where working backups are stored (default: current directory)
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

See [`configs/`](./configs) for example configuration files.

``` 
configs/
├── bash-project.ilma.conf    ✔ sh,bash,conf ..    ✖ log,tmp ..
├── default.conf              ✔ md,txt ..          ✖ .git,.ilma.conf ..
├── latex-project.ilma.conf   ✔ tex,bbl ..         ✖ .aux,.log,.synctex.gz ..
├── minimal.ilma.conf         ✔ md,txt ..
├── node-project.ilma.conf    ✔ js,ts,md,json ..   ✖ node_modules,package-lock.json ..
└── python-project.ilma.conf  ✔ py,md,yaml ..      ✖ .pyc,__pycache__,venv ..
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

## ABC Architecture

**`ilma`** optionally provides an Archive-Backup-Context pattern.  The behavior is controlled by the `.ilma.conf` file in the project root.

```
../
├── archive/project-timestamp.tar.zst  # Compressed archives
├── backup/project.bak/                # Full backups  
└── context/project/                   # Context mirrors
```

You can make use of **`ilma`**'s configuration to intelligently clean up build artifacts and other junk files.
Run with `ilma prune --bak my-project` to create a complete snapshot of your project, while removing junk files.

``` bash
my-projects$ ilma prune dissertation/ --type latex  # [options] 
# options: --verbose, --bak, --delete
```

``` text
Directory: /home/me/my-projects/dissertation
Type: latex

Found 22 junk items

Preview (first 5 items):
  one-gamma-vs-density.aux
  31-dissertation-defense.aux
  ejecta.aux
  initial-data.aux
  matter.aux
  ... and 17 more items

Use --verbose to see detailed analysis
```

## License
[GPLv3](https://www.gnu.org/licenses/gpl-3.0.txt)

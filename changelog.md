# changelog

recent development work on ilma backup/archive tool, roughly chronological

## september 2025

### 2025-09-06 short forms and multiple operations
- added short flags: `-a` archive, `-b` backup, `-c` context, `-e` encrypt, `-r` remote
- multi-operation support: `ilma -aec` creates archive, context, and encrypted versions in one run
- fixed regression: validate command args broken (`--dependencies`, `--gpg`, `--compression`)
- timestamp/numbered duplication handling restored for .bak files
- rsync output cleanup (removed verbose itemization spam)

### 2025-09-06 single file support
- single file backup: `file.txt` -> `file.txt.bak` (or numbered/timestamped)
- single file encryption: `file.txt` -> `file.txt.gpg`
- handles pre-archived files: `project.tar.zst` -> `project.tar.zst.gpg`
- `--target` flag added for custom output directories (replaces `--outdir`)

### 2025-09-06 multi-origin archives
- multiple path arguments: `ilma -a dir1/ dir2/ dir3/`
- creates single archive from multiple sources with timestamp naming
- works with encryption: `ilma -ae path1 path2`
- proper source listing in output
- fixed bug where only first path was processed

### 2025-09-06 custom naming and targeting
- `--basename NAME` for custom output filenames
- combines with `--target`: `--target /path --basename myfile` -> `/path/myfile.tar.zst`
- works across all mirror types (-a, -b, -c, -e)
- replaces auto-generated timestamps when specified

### 2025-09-07 pipeline encryption
- direct tar -> gpg pipeline eliminates temp files in `/tmp`
- removes intermediate disk i/o for encryption
- maintains all logic for exclusions and multi-origin support

### 2025-09-12 scan and prune improvements
- multi-type support: `--type all`, repeated flags, pipe-separated lists
- pattern-based operations: `--pattern "*.log"` independent of project type
- strict argument order enforcement: `ilma COMMAND [OPTIONS] [PATH]`
- prune verbose output with size summaries
- safety: excludes .git and vcs paths from deletion

### 2025-09-12 filesystem optimizations
- smart copy detection for local mirrors
- filesystem-aware performance: btrfs reflinks, ext4 optimizations
- benchmark results show 3-8x speedup over rsync for local copies
- fallback to rsync for remote/cross-filesystem operations
- affects backup mirrors, not context mirrors

## implementation notes

completed regressions fixes:
- timestamp/mirror duplication handling
- validate command argument parsing
- rsync output cleanup

completed core functionality:
- short form flags (-abcer)
- multiple mirror operations in single command
- single file backup and encryption
- multi-origin archive creation
- custom output naming and targeting
- temp-file-free encryption pipeline
- filesystem detection and optimization

pending work:
- trash method for prune with restoration
- statistics summary for file extensions
- absolute vs relative mirror path configuration
- commutative remote flag with other operations

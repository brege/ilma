# ilma/lib/ - Modular Architecture Overview

The `lib/` directory contains the core functionality of **ilma**, organized into standalone tools and reusable function libraries.

## Architecture

### Standalone Tools - Executables
|                   |                                          |
|-------------------|------------------------------------------|
| **`backup.sh`**   | Main backup functionality                |
| **`config.sh`**   | Configuration loading and validation     |
| **`console.sh`**  | Project statistics and analysis          |
| **`excludes.sh`** | Utility for processing exclusion configs |
| **`scan.sh`**     | Project scanner with junk file detection |

The above scripts can be run directly, have `--help` flags, and include their own entry points.

### Function Libraries - Non-Executables

|                      |                                             |
|----------------------|---------------------------------------------|
| **`compression.sh`** | Archive compression utils (zstd, gzip, .. ) | 
| **`functions.sh`**   | Core utility functions (line & file stats)  |
| **`gpg.sh`**         | GPG encryption/decryption functions         |
| **`prune.sh`**       |  File cleanup and pruning functions         |
| **`rsync.sh`**       | Remote synchronization functions            |

Pure function collections sourced by other scripts.

---

For the current scope, all of these utilities and functions are flattened in the `lib/` directory.

## Standalone Tools in `lib/`

**`backup.sh`**
```bash
# backup a project
./commands/backup.sh /path/to/project

# or w/ archive creation
ARCHIVE_FLAG=--archive ./commands/backup.sh /path/to/project
```

**`config.sh`**
```bash
# test config loading
./commands/config.sh /path/to/project

# validate config/inheritance
./commands/config.sh /path/to/project-with-ilma-conf
```

**`console.sh`**
```bash
# project statistics
./commands/console.sh /path/to/project

# analyze current directory
./commands/console.sh
```

**`excludes.sh`**
```bash
# process several configs
./lib/excludes.sh config1.conf config2.conf

# output exclusion arrays for scripting
eval "$(./lib/excludes.sh project.conf)"
echo "Skip dirs: ${SKIP_DIRS[@]}"
```

**`scan.sh`**
```bash
# Scan project for junk files
./commands/scan.sh /path/to/project

# Scan with project type detection
./commands/scan.sh /path/to/project --detect-type
```

## Function Libraries

**Function Library Usage**
```bash
#!/bin/bash
# source required libraries
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "$ILMA_DIR/lib/deps/compression.sh"
source "$ILMA_DIR/lib/functions.sh"

# use library functions
archive_ext=$(get_archive_extension "zstd")
line_count=$(git-count-lines "/path/to/project" "*.py")
```

**Configuration Loading Pattern**
```bash
# standard config loading in standalone tools
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    PROJECT_ROOT="${1:-$(pwd)}"
    
    source "$ILMA_DIR/commands/config.sh"
    load_config "$PROJECT_ROOT"
    
    # Tool-specific functionality here
fi
```

#!/usr/bin/env bash
# scanner.sh - Universal project scanner using ilma configuration patterns
# Detects project files and junk/build artifacts based on ilma config exclusions

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS] [directory]"
    echo ""
    echo "Options:"
    echo "  --config FILE    Use specific ilma config file"
    echo "  --type TYPE      Use predefined config type (latex, node, python)"
    echo "  --stats          Show summary statistics"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --type latex ./my-project"
    echo "  $0 --config .ilma.conf ."
    echo "  $0 --stats ~/projects/latex-doc"
    exit 1
}

# Parse arguments
STATS=0
DIR="."
CONFIG_FILE=""
CONFIG_TYPE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stats) STATS=1; shift ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --type) CONFIG_TYPE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) DIR="$1"; shift ;;
    esac
done

# Determine config source
ILMA_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

if [[ -n "$CONFIG_TYPE" ]]; then
    case "$CONFIG_TYPE" in
        latex) CONFIG_FILE="$ILMA_DIR/examples/latex-project.ilma.conf" ;;
        node) CONFIG_FILE="$ILMA_DIR/examples/node-project.ilma.conf" ;;
        python) CONFIG_FILE="$ILMA_DIR/examples/python-project.ilma.conf" ;;
        *) echo "Error: Unknown config type '$CONFIG_TYPE'"; exit 1 ;;
    esac
elif [[ -z "$CONFIG_FILE" ]]; then
    # Look for config in target directory
    for config_name in ".ilma.conf" ".archive.conf" ".backup.conf"; do
        if [[ -f "$DIR/$config_name" ]]; then
            CONFIG_FILE="$DIR/$config_name"
            break
        fi
    done
    
    if [[ -z "$CONFIG_FILE" ]]; then
        echo "Error: No config file found. Use --config or --type option."
        exit 1
    fi
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file '$CONFIG_FILE' not found"
    exit 1
fi

echo "Using config: $CONFIG_FILE"
echo "Scanning directory: $DIR"
echo

# Load configuration with defaults
EXTENSIONS=(md txt)
RSYNC_EXCLUDES=()
PRIMARY_EXTENSION=""

source "$CONFIG_FILE"

# Set primary extension based on config type for project directory detection
if [[ -z "$PRIMARY_EXTENSION" ]]; then
    case "$CONFIG_TYPE" in
        latex) PRIMARY_EXTENSION="tex" ;;
        node) PRIMARY_EXTENSION="js" ;;
        python) PRIMARY_EXTENSION="py" ;;
        *) PRIMARY_EXTENSION="${EXTENSIONS[0]}" ;;
    esac
fi

# Get composite exclusions from all config files
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
eval "$("$SCRIPT_DIR/excludes.sh" "$SCRIPT_DIR/../examples"/*.conf)"

# Merge config-specific junk dirs with composite exclusions, removing duplicates  
ALL_JUNK_DIRS=("${JUNK_DIRS[@]}")
for common_dir in "${SKIP_DIRS[@]}"; do
    # Add if not already present
    if [[ ! " ${JUNK_DIRS[*]} " =~ \ ${common_dir}\  ]]; then
        ALL_JUNK_DIRS+=("$common_dir")
    fi
done

# Convert RSYNC_EXCLUDES to patterns we can use with find
JUNK_PATTERNS=()
JUNK_DIRS=()

for exclude in "${RSYNC_EXCLUDES[@]}"; do
    if [[ "$exclude" == "--exclude" ]]; then
        continue
    fi
    
    # Remove trailing slash for directories
    pattern="${exclude%/}"
    
    if [[ "$pattern" == *"*"* ]]; then
        # Glob pattern - use as file pattern
        JUNK_PATTERNS+=("$pattern")
    elif [[ "$exclude" == *"/" ]]; then
        # Directory pattern
        JUNK_DIRS+=("$pattern")
    else
        # Could be file or dir, treat as both
        JUNK_PATTERNS+=("$pattern")
        JUNK_DIRS+=("$pattern")
    fi
done

# Build exclusion args for all find operations to prevent recursion into junk dirs
FIND_EXCLUDE_ARGS=()
for dir_pattern in "${ALL_JUNK_DIRS[@]}"; do
    FIND_EXCLUDE_ARGS+=(-name "${dir_pattern}" -o)
done
if (( ${#FIND_EXCLUDE_ARGS[@]} > 0 )); then
    unset 'FIND_EXCLUDE_ARGS[-1]'  # Remove trailing -o
fi

# Find source files based on EXTENSIONS using efficient mapfile with exclusions
SOURCE_FILES=()
for ext in "${EXTENSIONS[@]}"; do
    if (( ${#FIND_EXCLUDE_ARGS[@]} > 0 )); then
        mapfile -d '' -t ext_files < <(find "$DIR" \( "${FIND_EXCLUDE_ARGS[@]}" \) -prune -o -type f -name "*.${ext}" -print0 2>/dev/null || true)
    else
        mapfile -d '' -t ext_files < <(find "$DIR" -type f -name "*.${ext}" -print0 2>/dev/null || true)
    fi
    SOURCE_FILES+=("${ext_files[@]}")
done

# Find junk files and directories using efficient mapfile with exclusions
JUNK_ITEMS=()

# Find junk files using patterns
for pattern in "${JUNK_PATTERNS[@]}"; do
    if (( ${#FIND_EXCLUDE_ARGS[@]} > 0 )); then
        mapfile -d '' -t pattern_files < <(find "$DIR" \( "${FIND_EXCLUDE_ARGS[@]}" \) -prune -o -type f -name "$pattern" -print0 2>/dev/null || true)
    else
        mapfile -d '' -t pattern_files < <(find "$DIR" -type f -name "$pattern" -print0 2>/dev/null || true)
    fi
    JUNK_ITEMS+=("${pattern_files[@]}")
done

# Find junk directories - report them but don't recurse inside them
for dir_pattern in "${JUNK_DIRS[@]}"; do
    mapfile -d '' -t pattern_dirs < <(find "$DIR" -type d -name "$dir_pattern" -print0 2>/dev/null)
    for dir in "${pattern_dirs[@]}"; do
        # Only add if it's not inside another junk directory
        is_nested=false
        for check_pattern in "${ALL_JUNK_DIRS[@]}"; do
            if [[ "$dir" == *"/${check_pattern}/"* ]]; then
                is_nested=true
                break
            fi
        done
        if [[ "$is_nested" == false ]]; then
            JUNK_ITEMS+=("$dir/")
        fi
    done
done

if (( STATS == 1 )); then
    # Stats mode - per-project directory analysis like original latex scanner
    
    # Find all directories containing primary files (project nodes) - exclude junk dirs properly
    FIND_EXCLUDES=()
    for dir_pattern in "${JUNK_DIRS[@]}"; do
        FIND_EXCLUDES+=(-path "*/${dir_pattern}" -prune -o)
    done
    
    # Build composite exclusions from all configs to prevent deep recursion
    EXCLUDE_ARGS=()
    for dir_pattern in "${ALL_JUNK_DIRS[@]}"; do
        EXCLUDE_ARGS+=(-name "${dir_pattern}" -o)
    done
    # Remove the trailing -o
    if (( ${#EXCLUDE_ARGS[@]} > 0 )); then
        unset 'EXCLUDE_ARGS[-1]'
    fi
    
    # Find project directories with composite exclusions
    mapfile -t project_dirs < <(
        if (( ${#EXCLUDE_ARGS[@]} > 0 )); then
            find "$DIR" \( "${EXCLUDE_ARGS[@]}" \) -prune -o -type f -name "*.${PRIMARY_EXTENSION}" -print | while read -r file; do dirname "$file"; done | sort -u
        else
            find "$DIR" -type f -name "*.${PRIMARY_EXTENSION}" -exec dirname {} \; | sort -u  
        fi
    )
    
    if (( ${#project_dirs[@]} == 0 )); then
        echo "No project directories found in $DIR."
        exit 0
    fi
    
    # Print header with well-aligned columns
    printf "%-60s %10s %12s %15s\n" "Project Directory" "Source Files" "Junk Files" "Junk Size"
    printf "%-60s %10s %12s %15s\n" "-----------------" "------------" "----------" "---------"
    
    for proj_dir in "${project_dirs[@]}"; do
        # Count source files in proj_dir (non-recursive)
        source_count=0
        for ext in "${EXTENSIONS[@]}"; do
            count=$(find "$proj_dir" -maxdepth 1 -type f -name "*.${ext}" | wc -l)
            ((source_count += count))
        done

        # Collect junk files matching patterns (non-recursive)
        mapfile -t junk_files < <(
            {
                for pat in "${JUNK_PATTERNS[@]}"; do
                    find "$proj_dir" -maxdepth 1 -type f -name "$pat"
                done
                # Include junk directories
                for dir_pat in "${JUNK_DIRS[@]}"; do
                    find "$proj_dir" -maxdepth 1 -type d -name "$dir_pat"
                done
            } 2>/dev/null
        )

        junk_count=${#junk_files[@]}

        if (( junk_count > 0 )); then
            # Calculate total size of junk files + dirs in human readable format
            total_bytes=0
            for jf in "${junk_files[@]}"; do
                if [[ -e "$jf" ]]; then
                    size=$(du -sb "$jf" | cut -f1)
                    total_bytes=$((total_bytes + size))
                fi
            done

            # Format total_bytes to human readable form
            human_size=$(numfmt --to=iec --suffix=B "$total_bytes")
        else
            human_size="0B"
        fi

        # Print the info line with padding (skip if no junk)
        if (( junk_count > 0 )); then
            printf "%-60s %10d %12d %15s\n" "$proj_dir" "$source_count" "$junk_count" "$human_size"
        fi
    done
    
else
    # Detailed listing mode
    if (( ${#SOURCE_FILES[@]} > 0 )); then
        echo "Source files (${#SOURCE_FILES[@]}):"
        for file in "${SOURCE_FILES[@]}"; do
            echo -e "  ${GREEN}${file}${RESET}"
        done
        echo
    else
        echo "No source files found matching extensions: ${EXTENSIONS[*]}"
        echo
    fi
    
    if (( ${#JUNK_ITEMS[@]} > 0 )); then
        echo "Junk/build files (${#JUNK_ITEMS[@]}):"
        for item in "${JUNK_ITEMS[@]}"; do
            if [[ -d "$item" ]]; then
                echo -e "  ${YELLOW}${item}${RESET}"
            else
                echo -e "  ${RED}${item}${RESET}"
            fi
        done
    else
        echo "No junk files found."
    fi
fi

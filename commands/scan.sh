#!/usr/bin/env bash
# commands/scan.sh - General-purpose dry-run skip printer with LaTeX-style project detection

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
CONF_DIR="$ILMA_DIR/configs"

# Find all .ilma.conf files
mapfile -t config_files < <(find "$CONF_DIR" -maxdepth 1 -type f -name '*.ilma.conf' | sort)

declare -A types_map=()
for cf in "${config_files[@]}"; do
    basefile="$(basename "$cf")"
    name="${basefile%.ilma.conf}"
    if [[ "$name" =~ ^(.+)-project$ ]]; then
        short_name="${BASH_REMATCH[1]}"
    else
        short_name="$name"
    fi
    types_map["$short_name"]="$cf"
done

DEFAULT_TYPE=""
TYPE="$DEFAULT_TYPE"
DIR="."
PRETTY_OUTPUT=false
STATS_MODE=""

usage() {
    cat <<EOF
Usage: $0 [--type TYPE] [--pretty] [directory]

  --type TYPE     Project type to use (required if no local .ilma.conf)
                  Supported types: ${!types_map[*]} all
                  Multiple types: --type node --type python OR --type 'node|python'
  --pretty        Human-friendly output with colors and headers
  directory       Directory to scan for projects (default: current dir)

This tool scans directories for projects and outputs junk file paths
according to the selected TYPE's exclude patterns or local .ilma.conf.

Use --type all to scan with all available *-project.ilma.conf configs.
Use multiple --type flags or pipe-separated values for combined patterns.

Default: machine-readable paths only (safe for piping)
With --pretty: human-friendly display with project context

Dry run mode only: no files are deleted.
EOF
    exit 1
}

# Parse arguments
while (( $# )); do
    case "$1" in
        --type)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --type requires an argument" >&2
                usage
            fi
            TYPE="$2"
            shift 2
            ;;
        --pretty)
            PRETTY_OUTPUT=true
            shift
            ;;
        --stats=*)
            STATS_MODE="${1#--stats=}"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

CONFIG_FILE=""
RSYNC_EXCLUDES=()

if [[ -z "$TYPE" ]]; then
    # No type specified - check for local .ilma.conf
    if [[ -f "$DIR/.ilma.conf" ]]; then
        # Load local config directly
        source "$DIR/.ilma.conf"
        CONFIG_FILE="$DIR/.ilma.conf (local)"
    else
        echo -e "${RED}Error:${RESET} --type is required when no local .ilma.conf found"
        echo "Supported types: ${!types_map[*]} all"
        exit 1
    fi
elif [[ "$TYPE" == "all" || "$TYPE" =~ \| ]]; then
    # Special case: use all configs or multiple types (pipe-separated)
    if [[ "$TYPE" == "all" ]]; then
        CONFIG_FILE="all project configs"
        # Use all *-project.ilma.conf configs
        for config_path in "${types_map[@]}"; do
            if [[ "$(basename "$config_path")" =~ -project\.ilma\.conf$ ]]; then
                source "$config_path"
            fi
        done
    else
        # Handle pipe-separated types: node|python|latex
        IFS='|' read -ra TYPES <<< "$TYPE"
        CONFIG_FILE="multiple types: ${TYPES[*]}"
        for single_type in "${TYPES[@]}"; do
            if [[ -z "${types_map[$single_type]:-}" ]]; then
                echo -e "${RED}Error:${RESET} Unsupported type '$single_type'"
                echo "Supported types: ${!types_map[*]} all"
                exit 1
            fi
            # Source each selected config
            source "${types_map[$single_type]}"
        done
    fi
elif [[ -z "${types_map[$TYPE]:-}" ]]; then
    echo -e "${RED}Error:${RESET} Unsupported type '$TYPE'"
    echo "Supported types: ${!types_map[*]} all"
    exit 1
else
    # Type specified - use type config
    CONFIG_FILE="${types_map[$TYPE]}"
    source "$CONFIG_FILE"
fi

# Parse exclude patterns
JUNK_PATTERNS=()
JUNK_DIRS=()
for exclude in "${RSYNC_EXCLUDES[@]}"; do
    if [[ "$exclude" == "--exclude" ]]; then
        continue
    fi
    # Strip quotes if any
    pattern="${exclude#\'}"
    pattern="${pattern%\'}"
    pattern="${pattern#\"}"
    pattern="${pattern%\"}"
    pattern="${exclude%/}"
    if [[ "$exclude" == */ ]]; then
        JUNK_DIRS+=("$pattern")
    else
        JUNK_PATTERNS+=("$pattern")
    fi
done

if [[ "$PRETTY_OUTPUT" == "true" ]]; then
    echo -e "${BLUE}Skip analysis for type '$TYPE' in directory: $DIR${RESET}"
    echo -e "${YELLOW}Dry run mode: no files will be deleted${RESET}"
    echo
fi

# For now, treat the specified directory as the project directory
# This can be enhanced later with type-specific project detection
project_dirs=("$DIR")

if [[ ! -d "$DIR" ]]; then
    if [[ "$PRETTY_OUTPUT" == "true" ]]; then
        echo "Directory not found: $DIR"
    fi
    exit 1
fi

# Build prune expression from parsed JUNK_DIRS (from RSYNC_EXCLUDES)
# Always exclude backup directories created by ilma
BACKUP_DIRS=(backup)
ALL_PRUNE_DIRS=("${JUNK_DIRS[@]}")
# Add backup directories and .bak pattern
for dir in "${BACKUP_DIRS[@]}"; do
    ALL_PRUNE_DIRS+=("$dir")
done
# Add .bak pattern matching
ALL_PRUNE_DIRS+=("*.bak")

PRUNE_EXPR=""
for pd in "${ALL_PRUNE_DIRS[@]}"; do
    [[ -n "$PRUNE_EXPR" ]] && PRUNE_EXPR+=" -o "
    PRUNE_EXPR+="-name $pd"
done

for proj_dir in "${project_dirs[@]}"; do
    if [[ "$PRETTY_OUTPUT" == "true" ]]; then
        echo -e "${GREEN}Project directory: $proj_dir${RESET}"
    fi
    all_junk=()

    for pat in "${JUNK_PATTERNS[@]}"; do
        while IFS= read -r -d '' f; do
            all_junk+=("$f")
        done < <(find "$proj_dir" \( $PRUNE_EXPR \) -prune -false -o -type f -name "$pat" -print0 2>/dev/null || true)
    done

    for dir_pat in "${JUNK_DIRS[@]}"; do
        while IFS= read -r -d '' d; do
            all_junk+=("$d/")
        done < <(find "$proj_dir" \( $PRUNE_EXPR \) -prune -false -o -type d -name "$dir_pat" -print0 2>/dev/null || true)
    done

    if (( ${#all_junk[@]} > 0 )); then
        if [[ "$STATS_MODE" == "excludes" ]]; then
            # Stats mode: count and summarize
            source "$ILMA_DIR/lib/stats.sh"
            echo -e "${RED}Found prunables:${RESET}"
            for item in "${all_junk[@]}"; do
                echo "$item"
            done | count_excludes
        elif [[ "$PRETTY_OUTPUT" == "true" ]]; then
            echo -e "  ${RED}WOULD DELETE:${RESET}"
            for item in "${all_junk[@]}"; do
                echo "    $item"
            done
        else
            # Machine-readable output: just the paths
            for item in "${all_junk[@]}"; do
                echo "$item"
            done
        fi
    else
        if [[ "$PRETTY_OUTPUT" == "true" ]]; then
            echo "  No junk files found."
        fi
    fi

    if [[ "$PRETTY_OUTPUT" == "true" ]]; then
        echo
    fi
done

if [[ "$PRETTY_OUTPUT" == "true" ]]; then
    echo -e "${YELLOW}Dry run complete: no files deleted${RESET}"
fi


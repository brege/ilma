#!/usr/bin/env bash
# lib/skip-paths.sh - General-purpose dry-run skip printer with LaTeX-style project detection

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
EXAMPLES_DIR="$SCRIPT_DIR/../configs"

# Find all .ilma.conf files
mapfile -t config_files < <(find "$EXAMPLES_DIR" -maxdepth 1 -type f -name '*.ilma.conf' | sort)

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

DEFAULT_TYPE="minimal"
TYPE="$DEFAULT_TYPE"
DIR="."
PRETTY_OUTPUT=false

usage() {
    cat <<EOF
Usage: $0 [--type TYPE] [--pretty] [directory]

  --type TYPE     Project type to use (default: $DEFAULT_TYPE)
                  Supported types: ${!types_map[*]}
  --pretty        Human-friendly output with colors and headers
  directory       Directory to scan for projects (default: current dir)

This tool scans directories containing .tex files as projects, and outputs
junk file paths according to the selected TYPE's exclude patterns.

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
        -h|--help)
            usage
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

if [[ -z "${types_map[$TYPE]:-}" ]]; then
    echo -e "${RED}Error:${RESET} Unsupported type '$TYPE'"
    echo "Supported types: ${!types_map[*]}"
    exit 1
fi

CONFIG_FILE="${types_map[$TYPE]}"

# Load config
RSYNC_EXCLUDES=()
source "$CONFIG_FILE"

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

# Find project directories containing .tex files
mapfile -t project_dirs < <(find "$DIR" -type f -name '*.tex' -exec dirname {} \; | sort -u)

if (( ${#project_dirs[@]} == 0 )); then
    if [[ "$PRETTY_OUTPUT" == "true" ]]; then
        echo "No projects (.tex files) found in $DIR."
    fi
    exit 0
fi

PRUNE_DIRS=(.git node_modules .svn)
PRUNE_EXPR=""
for pd in "${PRUNE_DIRS[@]}"; do
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
        if [[ "$PRETTY_OUTPUT" == "true" ]]; then
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


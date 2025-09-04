#!/usr/bin/env bash
# composite-excludes.sh - Collect all skip directories and file patterns from given .conf files
# Usage: composite-excludes.sh [config1.conf [config2.conf ...]]
# If a directory is given, attempts to locate .ilma.conf file within it automatically.

set -euo pipefail

declare -a SKIP_DIRS=()
declare -a SKIP_FILE_PATTERNS=()

usage() {
    cat <<EOF
Usage: $0 [PROJECT_PATH]

Aggregates all path exclusion patterns via input .ilma.conf's

ARGUMENTS:
  PROJECT_PATH Path to project directory, an .ilma.conf, or several dirs and confs

OPTIONS:
  -h, --help       Show this help message

OUTPUT:
  Prints two bash arrays:
    SKIP_DIRS           List of directories to skip
    SKIP_FILE_PATTERNS  List of file patterns to skip

Examples:
  $0 .ilma.conf                  # Process a specific config file
  $0 *-project.ilma.conf         # Process multiple config files
  $0 /path/to/my-project         # Process inferred .ilma.conf from my-project/

EOF
}

# Handle help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if (( $# == 0 )); then
    echo "Usage: $0 [PROJECT_PATH]"
    exit 1
fi

# Resolve config files from arguments
configs=()
for arg in "$@"; do
    if [[ -d "$arg" ]]; then
        conf="$arg/.ilma.conf"
        if [[ -f "$conf" ]]; then
            configs+=("$conf")
        else
            echo "Warning: Config file '$conf' not found in directory '$arg', skipping."
        fi
    elif [[ -f "$arg" ]]; then
        configs+=("$arg")
    else
        echo "Warning: File or directory '$arg' not found, skipping."
    fi
done

if (( ${#configs[@]} == 0 )); then
    echo "Error: No valid config files found."
    exit 1
fi

# Extract skip patterns from config files
for conf in "${configs[@]}"; do
    while IFS= read -r line; do
        # Normalize whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ "$line" =~ ^--exclude[[:space:]]+(.+) ]]; then
            pattern="${BASH_REMATCH[1]}"
            # Remove surrounding quotes if any
            pattern="${pattern#\'}"
            pattern="${pattern%\'}"
            pattern="${pattern#\"}"
            pattern="${pattern%\"}"
            # Classify as directory or file pattern
            if [[ "$pattern" == */ ]]; then
                # Directory pattern, strip trailing slash
                pattern="${pattern%/}"
                SKIP_DIRS+=("$pattern")
            elif [[ "$pattern" == *'*'* ]]; then
                # Glob file pattern
                SKIP_FILE_PATTERNS+=("$pattern")
            else
                # Ambiguous - add to both lists
                SKIP_FILE_PATTERNS+=("$pattern")
                SKIP_DIRS+=("$pattern")
            fi
        fi
    done < <(grep -- '--exclude' "$conf" || true)
done

# Remove duplicates preserving order
uniq_array() {
    declare -A seen
    for item in "$@"; do
        if [[ -z "${seen[$item]:-}" ]]; then
            seen[$item]=1
            echo "$item"
        fi
    done
}

mapfile -t SKIP_DIRS < <(uniq_array "${SKIP_DIRS[@]}")
mapfile -t SKIP_FILE_PATTERNS < <(uniq_array "${SKIP_FILE_PATTERNS[@]}")

# Output results as bash arrays
echo "SKIP_DIRS=("
for d in "${SKIP_DIRS[@]}"; do
    echo "  '$d'"
done
echo ")"
echo
echo "SKIP_FILE_PATTERNS=("
for f in "${SKIP_FILE_PATTERNS[@]}"; do
    echo "  '$f'"
done
echo ")"


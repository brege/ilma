#!/usr/bin/env bash
# composite-excludes.sh - Collect all skip directories and file patterns from given .conf files
# Usage: composite-excludes.sh conf1.conf conf2.conf ...
# Outputs two arrays: SKIP_DIRS and SKIP_FILE_PATTERNS

set -euo pipefail

declare -a SKIP_DIRS=()
declare -a SKIP_FILE_PATTERNS=()

if (( $# == 0 )); then
    echo "Usage: $0 config1.conf [config2.conf ...]"
    exit 1
fi

for conf in "$@"; do
    if [[ ! -f "$conf" ]]; then
        echo "Warning: Config file '$conf' not found, skipping."
        continue
    fi

    # Extract RSYNC_EXCLUDES array lines
    # We want to grab patterns inside --exclude 'PATTERN' or --exclude "PATTERN"
    # Respect possible mixed usage of quotes.
    # Example line: --exclude '*.aux'

    # Use grep + sed or bash read to extract patterns
    while IFS= read -r line; do
        # Remove leading/trailing spaces
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Only lines starting with --exclude
        if [[ "$line" =~ ^--exclude[[:space:]]+(.+) ]]; then
            pattern="${BASH_REMATCH[1]}"

            # Remove surrounding quotes if present
            pattern="${pattern#\'}"
            pattern="${pattern%\'}"
            pattern="${pattern#\"}"
            pattern="${pattern%\"}"

            # Check if this pattern looks like a directory pattern (ends with / or contains *)
            if [[ "$pattern" == */ ]]; then
                # Directory pattern, strip trailing slash for uniformity
                pattern="${pattern%/}"
                # Save directory
                SKIP_DIRS+=("$pattern")
            elif [[ "$pattern" == *'*'* ]]; then
                # Glob pattern, treat as file pattern
                SKIP_FILE_PATTERNS+=("$pattern")
            else
                # Ambiguous: treat as both file and dir pattern
                SKIP_FILE_PATTERNS+=("$pattern")
                SKIP_DIRS+=("$pattern")
            fi
        fi
    done < <(grep -- '--exclude' "$conf" || true)
done

# Remove duplicate entries keeping order (simple loop)
uniq_array() {
    declare -A seen
    local item
    for item in "$@"; do
        if [[ -z "${seen[$item]:-}" ]]; then
            seen[$item]=1
            echo "$item"
        fi
    done
}

# Unique arrays
mapfile -t SKIP_DIRS < <(uniq_array "${SKIP_DIRS[@]}")
mapfile -t SKIP_FILE_PATTERNS < <(uniq_array "${SKIP_FILE_PATTERNS[@]}")

# Output results as bash arrays (for sourcing or debugging)
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


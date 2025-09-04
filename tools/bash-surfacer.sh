#!/bin/bash
# surfacer.sh - Extract bash code patterns with function body truncation

set -eo pipefail

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [FILES/DIRS...]

Surface common Bash script code patterns

OPTIONS:
  --comments               show only code comments
  --comments=inline        show only inline code comments
  --echos                  show echo and printf commands
  --functions              show function definitions with truncated context
   -n NUM                   limit number of function body to head -N
  --heredoc                show only heredoc/help text/usage blocks
  --args                   show only command-line argument flags
  -R, --recursive          recursively scan directories for *.sh files
  -h, --help               show this help message and exit

ARGUMENTS:
  FILES/DIRS    A path, paths, globs, or directories (implicit ./*.sh)

EXAMPLES:
  $0 --comments -R .             # show all comments recursively in CWD
  $0 --functions -n 3 script.sh  # show first 3 lines of all functions
  $0 --comments=inline ./scripts # show inline comments, non-recursively
  $0 --args ~/tools              # show arguments supposedly used

EOF
}

PATTERN=""
RECURSIVE=false
LIMIT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --comments) PATTERN="comments"; shift ;;
        --comments=inline) PATTERN="comments-inline"; shift ;;
        --echos) PATTERN="echos"; shift ;;
        --functions) PATTERN="functions"; shift ;;
        --heredoc) PATTERN="heredoc"; shift ;;
        --args) PATTERN="args"; shift ;;
        -R|--recursive) RECURSIVE=true; shift ;;
        -n) LIMIT="$2"; shift 2 ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*) echo "Error: Unknown option $1" >&2; exit 1 ;;
        *) break ;;
    esac
done

[[ -z "$PATTERN" ]] && { echo "Error: Must specify pattern" >&2; exit 1; }
[[ $# -eq 0 ]] && { echo "Error: Must specify files/directories" >&2; exit 1; }

# Find shell files
files=()
for target in "$@"; do
    if [[ -f "$target" ]]; then
        files+=("$target")
    elif [[ -d "$target" ]]; then
        if [[ "$RECURSIVE" == true ]]; then
            while IFS= read -r -d '' file; do
                files+=("$file")
            done < <(find "$target" -name "*.sh" -type f -print0)
        else
            while IFS= read -r -d '' file; do
                files+=("$file")
            done < <(find "$target" -maxdepth 1 -name "*.sh" -type f -print0)
        fi
    fi
done

# Extract function with body truncation
extract_function() {
    local file="$1"
    local start_line="$2"

    echo "# $file:$start_line"

    # Find the end of function by counting braces
    local end_line
    end_line=$(awk -v start="$start_line" '
        NR >= start {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") brace++
                if (c == "}") brace--
                if (brace == 0 && NR > start) {
                    print NR
                    exit
                }
            }
        }' "$file")

    if [[ -n "$end_line" ]]; then
        local total_lines=$((end_line - start_line + 1))

        if [[ -n "$LIMIT" && $total_lines -gt $((LIMIT + 2)) ]]; then
            # Show truncated: signature + N lines + omitted + closing
            sed -n "${start_line},$((start_line + LIMIT))p" "$file"
            local omitted=$((total_lines - LIMIT - 2))
            echo "... ($omitted lines omitted) ..."
            sed -n "${end_line}p" "$file"
        else
            # Show full function
            sed -n "${start_line},${end_line}p" "$file"
        fi
    else
        # Just show the signature line
        sed -n "${start_line}p" "$file"
    fi
    echo
}

# Process based on pattern
case "$PATTERN" in
    comments)
        for file in "${files[@]}"; do
            if [[ -f "$file" ]]; then
                grep -Hn "^[[:space:]]*#[^!]" "$file" 2>/dev/null || true
            fi
        done
        ;;
    comments-inline)
        for file in "${files[@]}"; do
            if [[ -f "$file" ]]; then
                grep -Hn -E "[^#]*[[:space:]]#[[:space:]]" "$file" 2>/dev/null || true
            fi
        done
        ;;
    echos)
        for file in "${files[@]}"; do
            if [[ -f "$file" ]]; then
                grep -Hn -E "(^|[[:space:]])(echo|printf)[[:space:]]" "$file" 2>/dev/null || true
            fi
        done
        ;;
    heredoc)
        for file in "${files[@]}"; do
            [[ -f "$file" ]] || continue
            # Find heredocs and extract their full content
            awk '/<<[[:space:]]*['\''"]?[A-Z_]+['\''"]?/ {
                start = NR
                delimiter = $0
                gsub(/.*<<[[:space:]]*['\''"]?/, "", delimiter)
                gsub(/['\''"]?.*/, "", delimiter)
                print "# " FILENAME ":" start
                print $0
                while ((getline line) > 0) {
                    if (line == delimiter) {
                        print line
                        print ""
                        break
                    }
                    print line
                }
            }' "$file" 2>/dev/null || true
        done
        ;;
    args)
        for file in "${files[@]}"; do
            [[ -f "$file" ]] || continue
            echo "# $file - Arguments used in code:"
            grep -v '^[[:space:]]*#' "$file" 2>/dev/null | grep -oE -- '--[a-zA-Z0-9_-]+' | grep -v -E '\-{3,}' | sort -u | sed 's/^/  /'
            echo "# $file - Arguments in help text:"
            # Extract from usage/help functions
            awk '/^usage\(\)|^[[:space:]]*cat.*<<.*EOF/,/^EOF$|^}$/ {
                if (match($0, /--[a-zA-Z0-9_-]+/)) {
                    while (match($0, /--[a-zA-Z0-9_-]+/)) {
                        print "  " substr($0, RSTART, RLENGTH)
                        $0 = substr($0, RSTART + RLENGTH)
                    }
                }
            }' "$file" 2>/dev/null | sort -u
            echo
        done
        ;;
    functions)
        for file in "${files[@]}"; do
            [[ -f "$file" ]] || continue
            grep -n -E "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)" "$file" 2>/dev/null | while IFS=: read -r line_num func_line; do
                extract_function "$file" "$line_num"
            done
        done
        ;;
esac


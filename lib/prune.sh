#!/bin/bash
# lib/prune.sh - Simple prune functionality using scan.sh

ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

usage() {
    cat <<EOF
Usage: ilma prune [OPTIONS] [PROJECT_PATH]

Analyze and optionally remove junk files from projects based on project type configuration.

OPTIONS:
  --type TYPE      Project type configuration to use (default: minimal)
                   Available types: default, minimal, bash, latex, node, python
  --verbose        Show detailed analysis with file paths and context
  --bak            Create complete backup before deleting files
  --delete         Delete junk files without creating backup (DANGEROUS)
  -h, --help       Show this help message

MODES:
  Default          Dry-run analysis only - shows summary of junk files found
  --verbose        Detailed dry-run with full file listing
  --bak            Creates complete compressed backup then deletes junk files
  --delete         Deletes junk files immediately (no backup created)

EXAMPLES:
  ilma prune                           # Dry-run analysis of current directory
  ilma prune --verbose                 # Detailed analysis with file paths
  ilma prune --type python --verbose   # Analyze Python project with details
  ilma prune --type latex --bak        # Backup LaTeX project then clean
  ilma prune --delete                  # Delete junk files (no backup)

SAFETY:
  - Default mode is always dry-run (no files deleted)
  - --bak creates complete project backup before deletion
  - --delete mode bypasses backup creation
  - Use --verbose to preview what will be deleted before using --bak or --delete

EOF
    exit 0
}

do_prune() {
    local project_root="$1"
    local verbose="${2:-false}"
    local type="${3:-$TYPE}"
    local delete_mode="${4:-false}"
    local project_name
    project_name="$(basename "$project_root")"

    echo "Prune analysis for: $project_name"
    echo "Directory: $project_root"
    echo "Type: $type"
    echo

    if [[ "$delete_mode" == "true" ]]; then
        # Delete mode: just do it, no previews or warnings
        mapfile -t files < <("$ILMA_DIR/lib/scan.sh" --type "$type" "$project_root")
        if (( ${#files[@]} == 0 )); then
            echo "No junk files found - project appears clean!"
            return 0
        fi

        # Initialize logging for destructive operation
        source "$ILMA_DIR/lib/log.sh"
        local log_file
        log_file="$(get_log_file "prune")"
        init_log "$log_file" "prune" "$project_root"
        log_summary "$log_file" "Starting prune operation on ${#files[@]} files"

        echo "Logging operation to: $log_file"

        local deleted=0
        local failed=0
        for file in "${files[@]}"; do
            if rm -rf "$file" 2>/dev/null; then
                echo "DELETED: $file"
                log_file_op "$log_file" "DELETE" "$file" "SUCCESS"
                ((deleted++))
            else
                echo "FAILED: $file"
                log_file_op "$log_file" "DELETE" "$file" "FAILED"
                ((failed++))
            fi
        done

        log_summary "$log_file" "Prune operation completed: $deleted deleted, $failed failed"
        echo "Operation logged to: $log_file"
    elif [[ "$verbose" == "true" ]]; then
        # Verbose dry-run: show detailed analysis
        "$ILMA_DIR/lib/scan.sh" --type "$type" --pretty "$project_root"
    else
        # Default dry-run: show summary and preview
        mapfile -t files < <("$ILMA_DIR/lib/scan.sh" --type "$type" "$project_root")
        if (( ${#files[@]} == 0 )); then
            echo "No junk files found - project appears clean!"
            return 0
        fi

        echo "Found ${#files[@]} junk items"
        echo
        echo "Preview (first 5 items):"
        for ((i=0; i<5 && i<${#files[@]}; i++)); do
            echo "  $(basename "${files[i]}")"
        done
        if (( ${#files[@]} > 5 )); then
            echo "  ... and $((${#files[@]} - 5)) more items"
        fi
        echo
        echo "Use --verbose to see detailed analysis"
        echo "Use --delete to remove these files"
    fi
}
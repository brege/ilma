#!/bin/bash
# lib/prune.sh - Simple prune functionality using scan.sh

ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

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
    if [[ "$delete_mode" == "true" ]]; then
        echo "DELETE MODE - Files will be permanently removed"
    else
        echo "DRY RUN ONLY - No files will be deleted"
    fi
    echo
    
    if [[ "$verbose" == "true" ]]; then
        "$ILMA_DIR/lib/scan.sh" --type "$type" --pretty "$project_root"
    else
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
    fi
    
    if [[ "$delete_mode" == "true" ]]; then
        echo
        echo "PERFORMING ACTUAL DELETION"
        echo "This is NOT a dry run - files will be permanently deleted"
        echo
        
        "$ILMA_DIR/lib/scan.sh" --type "$type" "$project_root" | while read -r file; do
            rm -rf "$file" && echo "DELETED: $file" || echo "FAILED: $file"
        done
        echo
        echo "Deletion complete"
    else
        echo "NOTE: This is a dry-run analysis only. No files were deleted."
    fi
}
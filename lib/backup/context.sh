#!/bin/bash
# lib/backup/context.sh - Context-only operations

# Create context mirror only (no full backup)
create_context_only() {
    local project_root="$1"
    local output_path="$2"
    local project_name
    project_name="$(basename "$project_root")"

    if [[ -z "$output_path" ]]; then
        # Default: create context in parent directory
        output_path="$(dirname "$project_root")/${project_name}-context"
    fi

    echo "Creating context mirror: $output_path"

    # Create context directory
    mkdir -p "$output_path"

    # Build rsync command for context files only
    local rsync_args=(
        "--archive"
        "--delete"
        "--human-readable"
        "--itemize-changes"
    )

    # Add context file patterns as includes
    if [[ ${#CONTEXT_FILES[@]} -gt 0 ]]; then
        for pattern in "${CONTEXT_FILES[@]}"; do
            rsync_args+=("--include=$pattern")
        done
        # Exclude everything else
        rsync_args+=("--exclude=*")
    else
        echo "Warning: No CONTEXT_FILES configured, creating minimal context"
        # Default context files
        rsync_args+=(
            "--include=README*"
            "--include=*.md"
            "--include=LICENSE*"
            "--include=CHANGELOG*"
            "--exclude=*"
        )
    fi

    # Add source and destination
    rsync_args+=("$project_root/")
    rsync_args+=("$output_path/")

    echo "Running: rsync ${rsync_args[*]}"

    if rsync "${rsync_args[@]}"; then
        echo "Context mirror created: $output_path"

        # Generate file listing
        if command -v tree >/dev/null 2>&1; then
            tree "$output_path" > "$output_path/TREE.txt"
        else
            find "$output_path" -type f | sort > "$output_path/FILES.txt"
        fi

        return 0
    else
        echo "Error: Failed to create context mirror" >&2
        return 1
    fi
}
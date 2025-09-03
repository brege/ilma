#!/bin/bash
# lib/backup/remote.sh - Remote synchronization operations

# Direct remote sync without local backup
sync_to_remote() {
    local project_root="$1"
    local remote_target="$2"
    local project_name
    project_name="$(basename "$project_root")"

    # Parse remote target (server:/path format)
    if [[ ! "$remote_target" =~ ^[^:]+:.+ ]]; then
        echo "Error: Remote target must be in format server:/path" >&2
        return 1
    fi

    echo "Syncing to remote: $remote_target"

    # Source rsync utilities
    source "$ILMA_DIR/lib/deps/rsync.sh"

    # Build rsync command
    local rsync_args=(
        "--archive"
        "--delete"
        "--human-readable"
        "--progress"
        "--itemize-changes"
    )

    # Add exclusions
    for exclude in "${RSYNC_EXCLUDES[@]}"; do
        if [[ "$exclude" == --exclude* ]]; then
            rsync_args+=("$exclude")
        fi
    done

    # Add source and destination
    rsync_args+=("$project_root/")
    rsync_args+=("$remote_target/$project_name/")

    echo "Running: rsync ${rsync_args[*]}"

    if rsync "${rsync_args[@]}"; then
        echo "Remote sync completed: $remote_target/$project_name/"
        return 0
    else
        echo "Error: Failed to sync to remote" >&2
        return 1
    fi
}

# Sync archive to remote
sync_archive_to_remote() {
    local archive_file="$1"
    local remote_target="$2"

    # Parse remote target
    if [[ ! "$remote_target" =~ ^[^:]+:.+ ]]; then
        echo "Error: Remote target must be in format server:/path" >&2
        return 1
    fi

    echo "Uploading archive to remote: $remote_target"

    local rsync_args=(
        "--archive"
        "--human-readable"
        "--progress"
        "--itemize-changes"
    )

    rsync_args+=("$archive_file")
    rsync_args+=("$remote_target/")

    echo "Running: rsync ${rsync_args[*]}"

    if rsync "${rsync_args[@]}"; then
        echo "Archive uploaded: $remote_target/$(basename "$archive_file")"
        return 0
    else
        echo "Error: Failed to upload archive" >&2
        return 1
    fi
}
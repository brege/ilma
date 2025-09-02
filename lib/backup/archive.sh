#!/bin/bash
# lib/backup/archive.sh - Archive-only operations

# Archive creation without full backup
create_archive_only() {
    local project_root="$1"
    local output_path="$2"
    local project_name
    project_name="$(basename "$project_root")"


    if [[ -z "$output_path" ]]; then
        # Default: create archive in parent directory
        output_path="$(dirname "$project_root")/${project_name}$(get_archive_extension "$COMPRESSION_TYPE")"
    fi

    echo "Creating archive: $output_path"

    # Source compression utilities
    source "$ILMA_DIR/lib/compression.sh"

    # Build tar command with exclusions
    local tar_args=("--create")
    local compression_option
    compression_option=$(get_tar_option "$COMPRESSION_TYPE")
    [[ -n "$compression_option" ]] && tar_args+=("$compression_option")

    # Add exclusions
    for exclude in "${RSYNC_EXCLUDES[@]}"; do
        if [[ "$exclude" == --exclude* ]]; then
            tar_args+=("$exclude")
        fi
    done

    tar_args+=("--file=$output_path")
    tar_args+=("-C" "$(dirname "$project_root")")
    tar_args+=("$project_name")

    if tar "${tar_args[@]}"; then
        echo "Archive created: $output_path"

        # Generate hash if configured
        if [[ -n "$HASH_ALGORITHM" ]]; then
            local hash_file="${output_path}.${HASH_ALGORITHM}"
            ${HASH_ALGORITHM}sum "$output_path" > "$hash_file"
            echo "Hash file created: $hash_file"
        fi

        return 0
    else
        echo "Error: Failed to create archive" >&2
        return 1
    fi
}
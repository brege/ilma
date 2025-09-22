#!/bin/bash
# lib/backup/archive.sh - Archive-only operations

# Source shared utility functions
source "$ILMA_DIR/lib/functions.sh"

# Archive path resolution with deduplication/versioning
resolve_archive_path_with_deduplication() {
    local base_path="$1"
    local naming_strategy="${ARCHIVE_VERSIONING:-timestamp}"

    # If file doesn't exist, use it as-is
    if [[ ! -f "$base_path" ]]; then
        echo "$base_path"
        return
    fi

    case "$naming_strategy" in
        "timestamp"|"force_timestamp")
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            local archive_ext
            archive_ext="$(get_archive_extension "$COMPRESSION_TYPE")"
            local basename="${base_path%"$archive_ext"}"
            echo "${basename}-${timestamp}${archive_ext}"
            ;;
        "numbered")
            local counter=1
            local archive_ext
            archive_ext="$(get_archive_extension "$COMPRESSION_TYPE")"
            local basename="${base_path%"$archive_ext"}"
            local numbered_path="${basename}.${counter}${archive_ext}"
            while [[ -f "$numbered_path" ]]; do
                ((counter++))
                numbered_path="${basename}.${counter}${archive_ext}"
            done
            echo "$numbered_path"
            ;;
        "overwrite")
            echo "$base_path"
            ;;
        *)
            # Default to timestamp
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            local archive_ext
            archive_ext="$(get_archive_extension "$COMPRESSION_TYPE")"
            local basename="${base_path%"$archive_ext"}"
            echo "${basename}-${timestamp}${archive_ext}"
            ;;
    esac
}

# Unified path resolution for *_base_dir settings
resolve_base_dir() {
    local base_dir="$1"
    local project_root="$2"
    local project_name="$3"
    local suffix="$4"

    if [[ -z "$base_dir" || "$base_dir" == ".." ]]; then
        # Default: sibling to project
        echo "$(dirname "$project_root")/${project_name}${suffix}"
    elif [[ "$base_dir" == "." ]]; then
        # Inside target directory - ERROR for archives
        echo "ERROR: archive_base_dir cannot be '.' (archives inside targets not supported)" >&2
        return 1
    elif [[ "$base_dir" == /* ]]; then
        # Absolute path
        echo "${base_dir/#\~/$HOME}/${project_name}${suffix}"
    else
        # Relative path - relative to project directory
        echo "$project_root/$base_dir/${project_name}${suffix}"
    fi
}

# Archive creation without full backup
create_archive_only() {
    local project_root="$1"
    local output_path="$2"
    local project_name
    project_name="$(basename "$project_root")"


    if [[ -z "$output_path" ]]; then
        # Default: create archive in parent directory with versioning
        local base_output_path
        base_output_path="$(dirname "$project_root")/${project_name}$(get_archive_extension "$COMPRESSION_TYPE")"
        if [[ "$ARCHIVE_VERSIONING" == "force_timestamp" ]]; then
            # Force timestamp even if file doesn't exist
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            local archive_ext
            archive_ext="$(get_archive_extension "$COMPRESSION_TYPE")"
            local basename="${base_output_path%"$archive_ext"}"
            output_path="${basename}-${timestamp}${archive_ext}"
        else
            output_path="$(resolve_archive_path_with_deduplication "$base_output_path")"
        fi
    fi

    echo "Creating archive: $output_path"

    # Source compression utilities
    source "$ILMA_DIR/lib/deps/compression.sh"

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

    # For single directory origins, avoid unnecessary nesting by archiving contents directly
    # Check if this is a single directory target (not a working directory with .git, etc.)
    local is_single_target=false
    if [[ -d "$project_root" ]] && [[ ! -f "$project_root/.ilma.conf" ]] && [[ ! -d "$project_root/.git" ]]; then
        # Appears to be a simple directory target rather than a project directory
        is_single_target=true
    fi

    if [[ "$is_single_target" == "true" ]]; then
        # Single directory case: archive contents directly to avoid nesting
        tar_args+=("-C" "$project_root")
        tar_args+=(".")
    else
        # Project directory or complex case: use encapsulating directory
        tar_args+=("-C" "$(dirname "$project_root")")
        tar_args+=("$project_name")
    fi

    # Estimate total size for progress indication
    local estimated_size=""
    if command -v pv >/dev/null 2>&1; then
        if [[ "$is_single_target" == "true" ]]; then
            estimated_size=$(du -sb "$project_root" 2>/dev/null | cut -f1)
        else
            estimated_size=$(du -sb "$project_root" 2>/dev/null | cut -f1)
        fi
    fi

    # Execute tar with progress indicator and compression ratio reporting
    if execute_with_progress "$estimated_size" "" "Error: Failed to create archive" tar "${tar_args[@]}"; then
        format_compression_message "Archive created: $output_path" "$output_path" "$estimated_size"
        return 0
    else
        return 1
    fi
}

# Archive creation for multiple origins
create_multi_origin_archive() {
    local output_path="$1"
    shift
    local paths=("$@")

    if [[ ${#paths[@]} -eq 0 ]]; then
        echo "Error: No paths provided for multi-origin archive" >&2
        return 1
    fi

    # Generate output path if not provided
    if [[ -z "$output_path" ]]; then
        local base_output_path
        base_output_path="./multi-origin$(get_archive_extension "$COMPRESSION_TYPE")"
        if [[ "$ARCHIVE_VERSIONING" == "force_timestamp" ]]; then
            # Force timestamp even if file doesn't exist
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            local archive_ext
            archive_ext="$(get_archive_extension "$COMPRESSION_TYPE")"
            local basename="${base_output_path%"$archive_ext"}"
            output_path="${basename}-${timestamp}${archive_ext}"
        else
            output_path="$(resolve_archive_path_with_deduplication "$base_output_path")"
        fi
    fi

    echo "Creating multi-origin archive: $output_path"
    echo "Sources: ${paths[*]}"

    # Source compression utilities
    source "$ILMA_DIR/lib/deps/compression.sh"

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

    # For multi-origin, we need to be careful about the working directory
    # Add all paths - tar will handle relative paths from current directory
    for path in "${paths[@]}"; do
        tar_args+=("$path")
    done

    # Estimate total size for progress indication
    local estimated_size=""
    if command -v pv >/dev/null 2>&1; then
        estimated_size=0
        for path in "${paths[@]}"; do
            if [[ -e "$path" ]]; then
                size=$(du -sb "$path" 2>/dev/null | cut -f1)
                estimated_size=$((estimated_size + size))
            fi
        done
    fi

    # Execute tar with progress indicator and compression ratio reporting
    if execute_with_progress "$estimated_size" "" "Error: Failed to create multi-origin archive" tar "${tar_args[@]}"; then
        format_compression_message "Multi-origin archive created: $output_path" "$output_path" "$estimated_size"
        return 0
    else
        return 1
    fi
}

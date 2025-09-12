#!/bin/bash
# lib/backup/encrypt.sh - Encryption operations

# Source shared utility functions
source "$ILMA_DIR/lib/functions.sh"

# Encrypt-only operation (creates encrypted archive using pipeline)
create_gpg() {
    local project_root="$1"
    local output_path="$2"
    local project_name
    project_name="$(basename "$project_root")"

    if [[ -z "$GPG_KEY_ID" ]]; then
        echo "Error: GPG_KEY_ID not configured for encryption" >&2
        return 1
    fi

    # Source required libraries
    source "$ILMA_DIR/lib/deps/compression.sh"
    source "$ILMA_DIR/lib/deps/gpg.sh"

    # Determine output path
    if [[ -z "$output_path" ]]; then
        output_path="$(dirname "$project_root")/${project_name}$(get_archive_extension "$COMPRESSION_TYPE")${GPG_OUTPUT_EXTENSION:-.gpg}"
    fi

    echo "Creating encrypted archive: $output_path"

    # Build tar command with exclusions for pipeline
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

    # Build tar and gpg command strings for pipeline execution
    local tar_cmd="tar $(printf '%q ' "${tar_args[@]}")"
    local gpg_cmd="gpg --yes --batch --encrypt --recipient '$GPG_KEY_ID' --trust-model always --quiet -o '$output_path'"

    # Execute tar→gpg pipeline with progress indicator and compression ratio reporting
    if execute_pipeline_with_progress "$estimated_size" "" "Error: Failed to create encrypted archive" "$tar_cmd" "$gpg_cmd"; then
        format_compression_message "Encrypted archive created: $output_path" "$output_path" "$estimated_size"
        return 0
    else
        return 1
    fi
}

# Encrypt existing file
encrypt_existing_file() {
    local input_file="$1"
    local output_file="$2"

    if [[ -z "$GPG_KEY_ID" ]]; then
        echo "Error: GPG_KEY_ID not configured for encryption" >&2
        return 1
    fi

    source "$ILMA_DIR/lib/deps/gpg.sh"

    if [[ -z "$output_file" ]]; then
        output_file="${input_file}${GPG_OUTPUT_EXTENSION:-.gpg}"
    fi

    echo "Encrypting: $input_file -> $output_file"

    if encrypt_file "$input_file" "$output_file"; then
        echo "File encrypted: $output_file"
        return 0
    else
        echo "Error: Failed to encrypt file" >&2
        return 1
    fi
}

# Encrypt-only operation for multiple origins (using pipeline)
create_multi_origin_gpg() {
    local output_path="$1"
    shift
    local paths=("$@")

    if [[ ${#paths[@]} -eq 0 ]]; then
        echo "Error: No paths provided for multi-origin encryption" >&2
        return 1
    fi

    if [[ -z "$GPG_KEY_ID" ]]; then
        echo "Error: GPG_KEY_ID not configured for encryption" >&2
        return 1
    fi

    # Generate output path if not provided
    if [[ -z "$output_path" ]]; then
        local timestamp
        timestamp="$(date '+%Y%m%d-%H%M%S')"
        output_path="./multi-origin-${timestamp}$(get_archive_extension "$COMPRESSION_TYPE")${GPG_OUTPUT_EXTENSION:-.gpg}"
    fi

    echo "Creating multi-origin encrypted archive: $output_path"
    echo "Sources: ${paths[*]}"

    # Source required libraries
    source "$ILMA_DIR/lib/deps/compression.sh"
    source "$ILMA_DIR/lib/deps/gpg.sh"

    # Build tar command with exclusions for pipeline
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

    # Add all paths for multi-origin
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

    # Build tar and gpg command strings for pipeline execution
    local tar_cmd="tar $(printf '%q ' "${tar_args[@]}")"
    local gpg_cmd="gpg --yes --batch --encrypt --recipient '$GPG_KEY_ID' --trust-model always --quiet -o '$output_path'"

    # Execute tar→gpg pipeline with progress indicator and compression ratio reporting
    if execute_pipeline_with_progress "$estimated_size" "" "Error: Failed to create encrypted archive" "$tar_cmd" "$gpg_cmd"; then
        format_compression_message "Multi-origin encrypted archive created: $output_path" "$output_path" "$estimated_size"
        return 0
    else
        return 1
    fi
}

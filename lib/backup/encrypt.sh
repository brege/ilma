#!/bin/bash
# lib/backup/encrypt.sh - Encryption operations

# Encrypt-only operation (creates encrypted archive)
create_encrypted_archive() {
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

    # Create temporary archive first
    local temp_archive
    temp_archive="/tmp/${project_name}-$$.$(get_archive_extension "$COMPRESSION_TYPE")"
    echo "Creating temporary archive for encryption..."

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

    tar_args+=("--file=$temp_archive")

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

    if ! tar "${tar_args[@]}"; then
        echo "Error: Failed to create temporary archive" >&2
        rm -f "$temp_archive"
        return 1
    fi

    # Determine output path
    if [[ -z "$output_path" ]]; then
        output_path="$(dirname "$project_root")/${project_name}$(get_archive_extension "$COMPRESSION_TYPE")${GPG_OUTPUT_EXTENSION:-.gpg}"
    fi

    echo "Encrypting archive to: $output_path"

    # Encrypt the archive
    if encrypt_file "$temp_archive" "$output_path"; then
        echo "Encrypted archive created: $output_path"
        rm -f "$temp_archive"
        return 0
    else
        echo "Error: Failed to encrypt archive" >&2
        rm -f "$temp_archive"
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

# Encrypt-only operation for multiple origins
create_multi_origin_encrypted_archive() {
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

    # Create temporary archive first
    local temp_archive
    temp_archive="/tmp/multi-origin-$$.$(get_archive_extension "$COMPRESSION_TYPE")"
    echo "Creating temporary archive for encryption..."

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

    tar_args+=("--file=$temp_archive")

    # Add all paths for multi-origin
    for path in "${paths[@]}"; do
        tar_args+=("$path")
    done

    if ! tar "${tar_args[@]}"; then
        echo "Error: Failed to create temporary archive" >&2
        rm -f "$temp_archive"
        return 1
    fi

    echo "Encrypting archive to: $output_path"

    # Encrypt the archive
    if encrypt_file "$temp_archive" "$output_path"; then
        echo "Multi-origin encrypted archive created: $output_path"
        rm -f "$temp_archive"
        return 0
    else
        echo "Error: Failed to encrypt archive" >&2
        rm -f "$temp_archive"
        return 1
    fi
}

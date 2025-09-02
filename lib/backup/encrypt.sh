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
    source "$ILMA_DIR/lib/compression.sh"
    source "$ILMA_DIR/lib/gpg.sh"

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
    tar_args+=("-C" "$(dirname "$project_root")")
    tar_args+=("$project_name")

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

    source "$ILMA_DIR/lib/gpg.sh"

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

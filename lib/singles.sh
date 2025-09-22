#!/bin/bash
# lib/single_file.sh - Single file backup and encryption functionality

# Source required dependencies
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "$ILMA_DIR/lib/functions.sh"
source "$ILMA_DIR/lib/deps/gpg.sh"

# Handle single file backup: file -> file.bak, file.1.bak, etc.
do_single_file_backup() {
    local file_path="$1"
    local file_name
    local file_dir
    file_name="$(basename "$file_path")"
    file_dir="$(dirname "$file_path")"

    # Determine backup naming strategy
    local naming_strategy="${VERSIONING:-timestamp}"
    local backup_file

    case "$naming_strategy" in
        "timestamp")
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            backup_file="${file_path}-${timestamp}.bak"
            ;;
        "numbered")
            local counter=1
            backup_file="${file_path}.${counter}.bak"
            while [[ -f "$backup_file" ]]; do
                ((counter++))
                backup_file="${file_path}.${counter}.bak"
            done
            ;;
        "overwrite")
            backup_file="${file_path}.bak"
            ;;
        *)
            # Default to timestamp
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            backup_file="${file_path}-${timestamp}.bak"
            ;;
    esac

    echo "Creating backup: $(basename "$backup_file")"
    cp "$file_path" "$backup_file"

    if [[ $? -eq 0 ]]; then
        local backup_size
        backup_size=$(du -sh "$backup_file" | cut -f1)
        echo "Backup created: $backup_size"
    else
        echo "Error: Failed to create backup"
        return 1
    fi
}

# Handle single file encryption: file -> file.gpg
do_single_file_encryption() {
    local file_path="$1"
    local output_file="${file_path}${GPG_OUTPUT_EXTENSION:-.gpg}"

    # Check if this exact file has already been encrypted by comparing checksums
    if [[ -f "$output_file" ]]; then
        # Check if the source file content matches what's already encrypted
        local source_hash existing_hash
        source_hash=$(sha256sum "$file_path" | cut -d' ' -f1)
        if command -v gpg >/dev/null 2>&1; then
            existing_hash=$(gpg --decrypt "$output_file" 2>/dev/null | sha256sum | cut -d' ' -f1)
            if [[ "$source_hash" == "$existing_hash" ]]; then
                echo "File already encrypted with identical content: $output_file"
                echo "Skipping encryption to avoid duplicate."
                return 0
            fi
        fi

        # If content differs or we can't decrypt, use naming strategy for uniqueness
        local naming_strategy="${ENCRYPT_VERSIONING:-timestamp}"
        case "$naming_strategy" in
            "timestamp"|"force_timestamp")
                local timestamp
                timestamp="$(date '+%Y%m%d-%H%M%S')"
                output_file="${file_path}-${timestamp}${GPG_OUTPUT_EXTENSION:-.gpg}"
                ;;
            "numbered")
                local counter=1
                local numbered_output="${file_path}.${counter}${GPG_OUTPUT_EXTENSION:-.gpg}"
                while [[ -f "$numbered_output" ]]; do
                    ((counter++))
                    numbered_output="${file_path}.${counter}${GPG_OUTPUT_EXTENSION:-.gpg}"
                done
                output_file="$numbered_output"
                ;;
            "overwrite")
                # Keep original output_file (will overwrite)
                ;;
        esac
    fi

    # Use existing encrypt_file function from lib/deps/gpg.sh
    if encrypt_file "$file_path" "$output_file"; then
        local encrypted_size
        encrypted_size=$(du -sh "$output_file" | cut -f1)
        echo "Encrypted file: $output_file ($encrypted_size)"
        return 0
    else
        echo "Error: Failed to encrypt file"
        return 1
    fi
}

# encrypt_file function is already provided by lib/deps/gpg.sh
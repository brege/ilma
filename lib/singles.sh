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
    local output_file="${file_path}.gpg"

    # If output already exists, use naming strategy for uniqueness
    if [[ -f "$output_file" ]]; then
        local naming_strategy="${VERSIONING:-timestamp}"
        case "$naming_strategy" in
            "timestamp")
                local timestamp
                timestamp="$(date '+%Y%m%d-%H%M%S')"
                output_file="${file_path}-${timestamp}.gpg"
                ;;
            "numbered")
                local counter=1
                local numbered_output="${file_path}.${counter}.gpg"
                while [[ -f "$numbered_output" ]]; do
                    ((counter++))
                    numbered_output="${file_path}.${counter}.gpg"
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
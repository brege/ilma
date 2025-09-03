#!/bin/bash
# commands/decrypt.sh - Decrypt and extract operations

ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Decrypt and optionally extract a GPG-encrypted file
do_decrypt() {
    local input_file="$1"
    local no_extract_flag="${2:-false}"
    local force_flag="${3:-false}"
    local outdir="${4:-}"

    if [[ -z "$input_file" ]]; then
        echo "Error: No input file specified for decryption" >&2
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        echo "Error: Input file does not exist: $input_file" >&2
        return 1
    fi

    # Source required libraries
    source "$ILMA_DIR/lib/deps/gpg.sh"
    source "$ILMA_DIR/lib/deps/compression.sh"

    # Decrypt first
    local output_file="${input_file%.gpg}"

    if ! decrypt_file "$input_file" "$output_file"; then
        return 1
    fi

    # If --no-extract flag is set, stop here
    if [[ "$no_extract_flag" == "true" ]]; then
        echo "Decryption complete: $output_file"
        return 0
    fi

    # If not an archive, nothing more to do
    if ! is_archive "$output_file"; then
        echo "Decryption complete: $output_file"
        return 0
    fi

    # Extract the archive using the same logic as extract command
    if extract_decrypted_archive "$output_file" "$force_flag" "$outdir"; then
        echo "Decryption and extraction complete: $(basename "$output_file" .tar.*)"
        return 0
    else
        return 1
    fi
}

# Extract a decrypted archive with conflict resolution
extract_decrypted_archive() {
    local archive_file="$1"
    local force_flag="${2:-false}"
    local outdir="${3:-}"

    # Determine target directory name using same logic as extract command
    local archive_base
    archive_base="$(basename "$archive_file")"

    local target_dir
    if [[ -n "$outdir" ]]; then
        # User specified output directory
        target_dir="$outdir"
    else
        # Use same directory naming logic as extract command
        if [[ "$archive_base" =~ \.[^.]+\.tar\. ]]; then
            # Complex case: preserve middle parts
            target_dir="$archive_base"
            target_dir="${target_dir%.tar.zst}"
            target_dir="${target_dir%.tar.gz}"
            target_dir="${target_dir%.tar.bz2}"
            target_dir="${target_dir%.tar.xz}"
            target_dir="${target_dir%.tar}"
            target_dir="${target_dir%.tgz}"
            target_dir="${target_dir%.tbz2}"
            target_dir="${target_dir%.txz}"
            target_dir="${target_dir%.gpg}"
        else
            # Simple case: remove all extensions
            target_dir="${archive_base%%.*}"
        fi
    fi

    # Handle directory conflicts
    if [[ -e "$target_dir" ]]; then
        if [[ "$force_flag" == "true" ]]; then
            echo "Removing existing directory: $target_dir"
            rm -rf "$target_dir"
        else
            echo "Error: Target directory already exists: $target_dir"
            echo "Use --force to replace, or --outdir to specify different location"
            return 1
        fi
    fi

    echo "Safely extracting $archive_file to $target_dir/"
    mkdir -p "$target_dir"

    # Extract using same logic as extract command
    local tar_option
    tar_option=$(get_tar_option "$archive_file")

    if [[ -n "$tar_option" ]]; then
        tar $tar_option -xf "$archive_file" -C "$target_dir"
    else
        tar -xf "$archive_file" -C "$target_dir"
    fi

    if [[ $? -eq 0 ]]; then
        echo "Archive extracted successfully to: $target_dir/"
        return 0
    else
        echo "Extraction failed"
        rmdir "$target_dir" 2>/dev/null
        return 1
    fi
}

# Enhanced extract with conflict resolution (for standalone extract command)
do_extract() {
    local archive_file="$1"
    local force_flag="${2:-false}"
    local outdir="${3:-}"

    if [[ -z "$archive_file" ]]; then
        echo "Error: No archive file specified for extraction" >&2
        return 1
    fi

    if [[ ! -f "$archive_file" ]]; then
        echo "Error: Archive file does not exist: $archive_file" >&2
        return 1
    fi

    source "$ILMA_DIR/lib/deps/compression.sh"

    if ! is_archive "$archive_file"; then
        echo "Error: File is not a recognized archive: $archive_file" >&2
        return 1
    fi

    # Use the same extraction logic as decrypt
    if extract_decrypted_archive "$archive_file" "$force_flag" "$outdir"; then
        # Show contents for standalone extract command
        if [[ -n "$outdir" ]]; then
            echo "Contents:"
            ls -la "$outdir/"
        else
            # Determine what directory was created using same logic
            local archive_base
            archive_base="$(basename "$archive_file")"
            local target_dir
            if [[ "$archive_base" =~ \.[^.]+\.tar\. ]]; then
                target_dir="$archive_base"
                target_dir="${target_dir%.tar.zst}"
                target_dir="${target_dir%.tar.gz}"
                target_dir="${target_dir%.tar.bz2}"
                target_dir="${target_dir%.tar.xz}"
                target_dir="${target_dir%.tar}"
                target_dir="${target_dir%.tgz}"
                target_dir="${target_dir%.tbz2}"
                target_dir="${target_dir%.txz}"
                target_dir="${target_dir%.gpg}"
            else
                target_dir="${archive_base%%.*}"
            fi
            echo "Contents:"
            ls -la "$target_dir/"
        fi
        return 0
    else
        return 1
    fi
}

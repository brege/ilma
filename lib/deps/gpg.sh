#!/bin/bash
# lib/deps/gpg.sh - GPG encryption and decryption functions

# Generic file encryption function
encrypt_file() {
    local input_file="$1"
    local output_file="$2"

    if [[ -z "$GPG_KEY_ID" ]]; then
        echo "Error: GPG_KEY_ID not configured" >&2
        return 1
    fi

    echo "Encrypting $input_file with GPG key ID $GPG_KEY_ID..."
    gpg --yes --batch --encrypt --recipient "$GPG_KEY_ID" -o "$output_file" "$input_file"

    if [[ $? -eq 0 ]]; then
        echo "Encryption successful: $output_file"
        return 0
    else
        echo "Encryption failed" >&2
        return 1
    fi
}

# Encrypt an existing archive file
encrypt_existing_archive() {
    local input_path="$1"
    local output_file="$2"
    local gpg_key_id="$3"

    echo "Encrypting archive $input_path to $output_file using GPG key ID $gpg_key_id..."
    gpg --yes --batch --encrypt --recipient "$gpg_key_id" -o "$output_file" "$input_path"

    if [[ $? -eq 0 ]]; then
        echo "Encryption successful."
        return 0
    else
        echo "Encryption failed."
        return 1
    fi
}

# Archive and encrypt in one step
archive_and_encrypt() {
    local input_path="$1"
    local output_file="$2"
    local gpg_key_id="$3"
    local compression_type="$4"
    local compression_level="$5"

    echo "Archiving and encrypting $input_path to $output_file using $compression_type compression..."

    local compression_cmd
    compression_cmd=$(get_compression_cmd "$compression_type" "$compression_level")

    if [[ "$compression_type" == "none" ]]; then
        tar -cf - "$input_path" | gpg --yes --batch --encrypt --recipient "$gpg_key_id" -o "$output_file"
    else
        tar -cf - "$input_path" | $compression_cmd | gpg --yes --batch --encrypt --recipient "$gpg_key_id" -o "$output_file"
    fi

    if [[ $? -eq 0 ]]; then
        echo "Archive and encryption successful."
        return 0
    else
        echo "Archive and encryption failed."
        return 1
    fi
}

# Decrypt a GPG encrypted file
decrypt_file() {
    local input_file="$1"
    local output_file="$2"

    echo "Decrypting $input_file to $output_file..."
    gpg --yes --batch --output "$output_file" --decrypt "$input_file"

    if [[ $? -eq 0 ]]; then
        echo "Decryption successful."
        return 0
    else
        echo "Decryption failed."
        return 1
    fi
}

# Extract an archive to a directory
extract_archive() {
    local archive_file="$1"
    local target_dir="$2"

    echo "Extracting archive to $target_dir..."
    mkdir -p "$target_dir"

    local tar_option
    tar_option=$(get_tar_option "$(get_compression_type_from_file "$archive_file")")
    if [[ -n "$tar_option" ]]; then
        tar $tar_option -xf "$archive_file" -C "$target_dir"
    else
        tar -xf "$archive_file" -C "$target_dir"
    fi

    if [[ $? -eq 0 ]]; then
        echo "Extraction successful to $target_dir"
        return 0
    else
        echo "Extraction failed."
        return 1
    fi
}
#!/usr/bin/env bash

# Load configuration from config.ini
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.ini"

# Check for alternative config file names
if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ -f "$SCRIPT_DIR/gpg-config.ini" ]]; then
        CONFIG_FILE="$SCRIPT_DIR/gpg-config.ini"
    elif [[ -f "$SCRIPT_DIR/.config.ini" ]]; then
        CONFIG_FILE="$SCRIPT_DIR/.config.ini"
    fi
fi

# Default values
DEFAULT_GPG_KEY_ID=""
DEFAULT_OUTPUT_EXTENSION=".gpg"
REMOTE_SERVER=""
REMOTE_PATH=""
DECRYPT_TARGET_DIR=""
CLEANUP_AFTER_TRANSFER="false"
HASH_ALGORITHM="sha256"
COMPRESSION_TYPE="zstd"
COMPRESSION_LEVEL="3"

# Compression library functions
function get_compression_cmd {
    local comp_type="$1"
    local comp_level="$2"

    case "$comp_type" in
        zstd)
            echo "zstd -${comp_level}"
            ;;
        gzip)
            echo "gzip -${comp_level}"
            ;;
        bzip2)
            echo "bzip2 -${comp_level}"
            ;;
        xz)
            echo "xz -${comp_level}"
            ;;
        lzma)
            echo "lzma -${comp_level}"
            ;;
        none)
            echo "cat"
            ;;
        *)
            echo "Unknown compression type: $comp_type" >&2
            exit 1
            ;;
    esac
}

function get_archive_extension {
    local comp_type="$1"

    case "$comp_type" in
        zstd) echo ".tar.zst" ;;
        gzip) echo ".tar.gz" ;;
        bzip2) echo ".tar.bz2" ;;
        xz) echo ".tar.xz" ;;
        lzma) echo ".tar.lzma" ;;
        none) echo ".tar" ;;
        *) echo ".tar" ;;
    esac
}

function get_tar_option {
    local comp_type="$1"

    case "$comp_type" in
        zstd) echo "-I zstd" ;;
        gzip) echo "-z" ;;
        bzip2) echo "-j" ;;
        xz) echo "-J" ;;
        lzma) echo "--lzma" ;;
        none) echo "" ;;
        *) echo "" ;;
    esac
}

function is_archive {
    local file="$1"
    [[ "$file" =~ \.(tar|tar\.gz|tar\.bz2|tar\.xz|tar\.zst|tar\.lzma|tgz|tbz2|txz)$ ]]
}

function is_compressed_archive {
    local file="$1"
    [[ "$file" =~ \.(tar\.gz|tar\.bz2|tar\.xz|tar\.zst|tar\.lzma|tgz|tbz2|txz)$ ]]
}

function get_compression_type_from_file {
    local file="$1"

    case "$file" in
        *.tar.zst) echo "zstd" ;;
        *.tar.gz|*.tgz) echo "gzip" ;;
        *.tar.bz2|*.tbz2) echo "bzip2" ;;
        *.tar.xz|*.txz) echo "xz" ;;
        *.tar.lzma) echo "lzma" ;;
        *.tar) echo "none" ;;
        *) echo "none" ;;
    esac
}

# Load config if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Remove quotes and whitespace
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | sed 's/^["'\'']*//;s/["'\'']*$//' | tr -d '[:space:]')

        case "$key" in
            gpg_key_id) DEFAULT_GPG_KEY_ID="$value" ;;
            output_extension) DEFAULT_OUTPUT_EXTENSION="$value" ;;
            remote_server) REMOTE_SERVER="$value" ;;
            remote_path) REMOTE_PATH="$value" ;;
            decrypt_target_dir) DECRYPT_TARGET_DIR="$value" ;;
            cleanup_after_transfer) CLEANUP_AFTER_TRANSFER="$value" ;;
            hash_algorithm) HASH_ALGORITHM="$value" ;;
            compression_type) COMPRESSION_TYPE="$value" ;;
            compression_level) COMPRESSION_LEVEL="$value" ;;
        esac
    done < "$CONFIG_FILE"
else
    echo "Warning: Config file not found at $CONFIG_FILE"
fi

function print_usage {
    echo "Usage:"
    echo "  $0 <path_or_archive> [--output <output_file>] [--gpg-key-id <key_id>] [--no-cleanup]"
    echo "  $0 --decrypt <encrypted_file> [--output <output_file>] [--target-dir <directory>]"
    echo ""
    echo "Options:"
    echo "  --output        Specify output file name"
    echo "  --gpg-key-id    GPG key ID for encryption (overrides config)"
    echo "  --target-dir    Target directory for decryption (overrides config)"
    echo "  --no-cleanup    Prevent removal of local encrypted file after transfer"
}

if [[ $# -lt 1 ]]; then
    print_usage
    exit 1
fi

MODE="encrypt"
INPUT_PATH=""
OUTPUT_FILE=""
GPG_KEY_ID="$DEFAULT_GPG_KEY_ID"
TARGET_DIR="$DECRYPT_TARGET_DIR"
NO_CLEANUP="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            shift
            OUTPUT_FILE="$1"
            ;;
        --gpg-key-id)
            shift
            GPG_KEY_ID="$1"
            ;;
        --target-dir)
            shift
            TARGET_DIR="$1"
            ;;
        --no-cleanup)
            NO_CLEANUP="true"
            ;;
        --decrypt)
            MODE="decrypt"
            ;;
        -*)
            echo "Unknown option $1"
            print_usage
            exit 1
            ;;
        *)
            if [[ -z "$INPUT_PATH" ]]; then
                INPUT_PATH="$1"
            else
                echo "Unexpected argument $1"
                print_usage
                exit 1
            fi
            ;;
    esac
    shift
done

if [[ ! -e "$INPUT_PATH" ]]; then
    echo "Input path does not exist: $INPUT_PATH"
    exit 1
fi

if [[ "$MODE" == "encrypt" ]]; then
    if [[ -z "$GPG_KEY_ID" ]]; then
        echo "GPG key ID not specified and not found in config"
        exit 1
    fi

    # Determine if we need to archive first
    if is_archive "$INPUT_PATH"; then
        # Already an archive - just encrypt
        if [[ -z "$OUTPUT_FILE" ]]; then
            OUTPUT_FILE="${INPUT_PATH}${DEFAULT_OUTPUT_EXTENSION}"
        fi

        echo "Encrypting archive $INPUT_PATH to $OUTPUT_FILE using GPG key ID $GPG_KEY_ID..."
        if gpg --yes --batch --encrypt --recipient "$GPG_KEY_ID" -o "$OUTPUT_FILE" "$INPUT_PATH"; then
            echo "Encryption successful."
        else
            echo "Encryption failed."
            exit 1
        fi
    else
        # Need to archive - do archival and encryption in one step
        ARCHIVE_EXT=$(get_archive_extension "$COMPRESSION_TYPE")
        ARCHIVE_NAME="$(basename "$INPUT_PATH")${ARCHIVE_EXT}"

        if [[ -z "$OUTPUT_FILE" ]]; then
            OUTPUT_FILE="${ARCHIVE_NAME}${DEFAULT_OUTPUT_EXTENSION}"
        fi

        echo "Archiving and encrypting $INPUT_PATH to $OUTPUT_FILE using $COMPRESSION_TYPE compression..."

        # Create archive and pipe directly to GPG
        COMPRESSION_CMD=$(get_compression_cmd "$COMPRESSION_TYPE" "$COMPRESSION_LEVEL")
        if [[ "$COMPRESSION_TYPE" == "none" ]]; then
            if tar -cf - "$INPUT_PATH" | gpg --yes --batch --encrypt --recipient "$GPG_KEY_ID" -o "$OUTPUT_FILE"; then
                echo "Archive and encryption successful."
            else
                echo "Archive and encryption failed."
                exit 1
            fi
        else
            if tar -cf - "$INPUT_PATH" | $COMPRESSION_CMD | gpg --yes --batch --encrypt --recipient "$GPG_KEY_ID" -o "$OUTPUT_FILE"; then
                echo "Archive and encryption successful."
            else
                echo "Archive and encryption failed."
                exit 1
            fi
        fi
    fi

    # Sync to remote if configured
    if [[ -n "$REMOTE_SERVER" && -n "$REMOTE_PATH" ]]; then
        echo "Computing local hash for verification..."
        LOCAL_HASH=$(${HASH_ALGORITHM}sum "$OUTPUT_FILE" | cut -d' ' -f1)
        echo "Local $HASH_ALGORITHM: $LOCAL_HASH"

        echo "Syncing encrypted archive to remote server $REMOTE_SERVER:$REMOTE_PATH..."

        # Use optimal rsync flags based on content type
        if is_compressed_archive "$INPUT_PATH" || [[ "$COMPRESSION_TYPE" != "none" ]]; then
            # Skip compression for already-compressed content
            if rsync -avP "$OUTPUT_FILE" "${REMOTE_SERVER}:${REMOTE_PATH}/"; then
                RSYNC_SUCCESS="true"
            else
                RSYNC_EXIT_CODE=$?
                echo "Rsync failed with exit code: $RSYNC_EXIT_CODE"
                RSYNC_SUCCESS="false"
            fi
        else
            # Use compression for uncompressed archives
            if rsync -avzP "$OUTPUT_FILE" "${REMOTE_SERVER}:${REMOTE_PATH}/"; then
                RSYNC_SUCCESS="true"
            else
                RSYNC_EXIT_CODE=$?
                echo "Rsync failed with exit code: $RSYNC_EXIT_CODE"
                RSYNC_SUCCESS="false"
            fi
        fi

        if [[ "$RSYNC_SUCCESS" == "true" ]]; then
            echo "Remote sync successful."

            # Verify remote file integrity
            echo "Verifying remote file integrity..."
            REMOTE_FILENAME=$(basename "$OUTPUT_FILE")
            #REMOTE_HASH=$(ssh "$REMOTE_SERVER" "${HASH_ALGORITHM}sum \"${REMOTE_PATH}/${REMOTE_FILENAME}\"" | cut -d' ' -f1)
            REMOTE_HASH=$(ssh "$REMOTE_SERVER" bash -c "$(printf '%q %q' "${HASH_ALGORITHM}sum" "${REMOTE_PATH}/${REMOTE_FILENAME}")" | cut -d' ' -f1)

            if [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]]; then
                echo "✓ Hash verification successful - remote file integrity confirmed"
                echo "Remote $HASH_ALGORITHM: $REMOTE_HASH"

                # Cleanup local encrypted file if configured and not explicitly disabled
                if [[ "$CLEANUP_AFTER_TRANSFER" == "true" && "$NO_CLEANUP" != "true" ]]; then
                    echo "Removing local encrypted file..."
                    if rm "$OUTPUT_FILE"; then
                        echo "Local cleanup successful."
                    else
                        echo "Warning: Failed to remove local encrypted file."
                    fi
                fi
            else
                echo "✗ Hash verification failed - remote file may be corrupted"
                echo "Local:  $LOCAL_HASH"
                echo "Remote: $REMOTE_HASH"
                echo "Keeping local encrypted file for safety."
                exit 1
            fi
        else
            echo "Remote sync failed."
            exit 1
        fi
    fi

else
    # Decrypt mode
    if [[ -z "$OUTPUT_FILE" ]]; then
        if [[ "$INPUT_PATH" == *.gpg ]]; then
            OUTPUT_FILE="${INPUT_PATH%.gpg}"
        else
            echo "Output file must be specified when decrypting non-.gpg files"
            exit 1
        fi
    fi

    echo "Decrypting $INPUT_PATH to $OUTPUT_FILE..."
    if gpg --yes --batch --output "$OUTPUT_FILE" --decrypt "$INPUT_PATH"; then
        echo "Decryption successful."

        # If target directory specified, extract there
        if [[ -n "$TARGET_DIR" && $(is_archive "$OUTPUT_FILE") ]]; then
            echo "Extracting archive to $TARGET_DIR..."
            mkdir -p "$TARGET_DIR"

            # Use library functions for extraction
            TAR_OPTION=$(get_tar_option "$(get_compression_type_from_file "$OUTPUT_FILE")")
            if [[ -n "$TAR_OPTION" ]]; then
                if tar $TAR_OPTION -xf "$OUTPUT_FILE" -C "$TARGET_DIR"; then
                    echo "Extraction successful to $TARGET_DIR"
                else
                    echo "Extraction failed."
                    exit 1
                fi
            else
                if tar -xf "$OUTPUT_FILE" -C "$TARGET_DIR"; then
                    echo "Extraction successful to $TARGET_DIR"
                else
                    echo "Extraction failed."
                    exit 1
                fi
            fi
        fi
    else
        echo "Decryption failed."
        exit 1
    fi
fi

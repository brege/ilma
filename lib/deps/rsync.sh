#!/bin/bash
# lib/deps/rsync.sh - Remote synchronization functions

# Compute file hash
compute_hash() {
    local file="$1"
    local algorithm="$2"

    case "$algorithm" in
        sha256)
            sha256sum "$file" | cut -d' ' -f1
            ;;
        sha1)
            sha1sum "$file" | cut -d' ' -f1
            ;;
        md5)
            md5sum "$file" | cut -d' ' -f1
            ;;
        *)
            echo "Unknown hash algorithm: $algorithm" >&2
            return 1
            ;;
    esac
}

# Sync file to remote server with verification
sync_to_remote() {
    local local_file="$1"
    local remote_server="$2"
    local remote_path="$3"
    local hash_algorithm="$4"
    local cleanup_after="${5:-false}"
    local no_cleanup="${6:-false}"

    echo "Computing local hash for verification..."
    local local_hash
    local_hash=$(compute_hash "$local_file" "$hash_algorithm")
    if [[ $? -ne 0 ]]; then
        echo "Failed to compute local hash"
        return 1
    fi
    echo "Local $hash_algorithm: $local_hash"

    echo "Syncing encrypted archive to remote server $remote_server:$remote_path..."

    # Use optimal rsync flags based on content type
    local rsync_opts="-avP"
    if is_compressed_archive "$(basename "$local_file")" || [[ "$local_file" =~ \.zst\.gpg$ ]]; then
        # Skip compression for already-compressed content
        rsync $rsync_opts "$local_file" "${remote_server}:${remote_path}/"
    else
        # Use compression for uncompressed archives
        rsync ${rsync_opts}z "$local_file" "${remote_server}:${remote_path}/"
    fi

    if [[ $? -ne 0 ]]; then
        echo "Remote sync failed."
        return 1
    fi

    echo "Remote sync successful."

    # Verify remote file integrity
    echo "Verifying remote file integrity..."
    local remote_hash
    remote_hash=$(ssh "$remote_server" '
      f=$(basename "'"$remote_path"'"/"'"$local_file"'")
      '"$hash_algorithm"'sum "$f"
    ' | cut -d" " -f1)

    if [[ "$local_hash" == "$remote_hash" ]]; then
        echo "✓ Hash verification successful - remote file integrity confirmed"
        echo "Remote $hash_algorithm: $remote_hash"

        # Cleanup local encrypted file if configured and not explicitly disabled
        if [[ "$cleanup_after" == "true" && "$no_cleanup" != "true" ]]; then
            echo "Removing local encrypted file..."
            rm "$local_file"
            if [[ $? -eq 0 ]]; then
                echo "Local cleanup successful."
            else
                echo "Warning: Failed to remove local encrypted file."
                return 1
            fi
        fi
        return 0
    else
        echo "✗ Hash verification failed - remote file may be corrupted"
        echo "Local:  $local_hash"
        echo "Remote: $remote_hash"
        echo "Keeping local encrypted file for safety."
        return 1
    fi
}

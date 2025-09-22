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
    local base_name
    base_name="$(basename "$local_file")"

    # Build a robust remote command: cd to path, then compute hash with fallbacks
    remote_hash=$(ssh "$remote_server" bash -s -- "$remote_path" "$base_name" "$hash_algorithm" << 'REMOTE_HASH_SH'
set -e
remote_path="$1"
file="$2"
algo="$3"
cd -- "$remote_path"
if command -v "${algo}sum" >/dev/null 2>&1; then
  "${algo}sum" -- "$file" | awk '{print $1}'
else
  case "$algo" in
    sha256)
      if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$file" | awk '{print $1}'; exit; fi
      if command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -- "$file" | awk '{print $2}'; exit; fi
      ;;
    sha1)
      if command -v shasum >/dev/null 2>&1; then shasum -a 1 -- "$file" | awk '{print $1}'; exit; fi
      if command -v openssl >/dev/null 2>&1; then openssl dgst -sha1 -- "$file" | awk '{print $2}'; exit; fi
      ;;
    md5)
      if command -v md5sum >/dev/null 2>&1; then md5sum -- "$file" | awk '{print $1}'; exit; fi
      if command -v md5 >/dev/null 2>&1; then md5 -q -- "$file" 2>/dev/null || md5 "$file" | awk '{print $NF}'; exit; fi
      if command -v openssl >/dev/null 2>&1; then openssl dgst -md5 -- "$file" | awk '{print $2}'; exit; fi
      ;;
  esac
  exit 127
fi
REMOTE_HASH_SH
)


    if [[ -n "$remote_hash" && "$local_hash" == "$remote_hash" ]]; then
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
        echo "Remote: ${remote_hash:-unavailable}"
        echo "Keeping local encrypted file for safety."
        return 1
    fi
}

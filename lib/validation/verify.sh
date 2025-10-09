#!/bin/bash
# lib/validation/verify.sh - Verification helpers for archives and mirrors

# Verify that a tar archive matches a source directory
# Usage: verify_archive_against_dir <archive_file> <project_root> <project_name>
verify_archive_against_dir() {
    local archive_file="$1"
    local project_root="$2"
    local project_name="$3"

    if [[ ! -f "$archive_file" ]]; then
        echo "Error: Archive not found for verification: $archive_file" >&2
        return 1
    fi

    source "$ILMA_DIR/lib/deps/compression.sh"

    local tar_option
    tar_option=$(get_tar_option "$(get_compression_type_from_file "$archive_file")")

    # Mirror the packing strategy from create_archive_only/create_gpg
    local is_single_target=false
    if [[ -d "$project_root" ]] && [[ ! -f "$project_root/.ilma.conf" ]] && [[ ! -d "$project_root/.git" ]]; then
        is_single_target=true
    fi

    echo "Verifying archive against source..."
    if [[ "$is_single_target" == "true" ]]; then
        if [[ -n "$tar_option" ]]; then
            tar $tar_option -df "$archive_file" -C "$project_root" .
        else
            tar -df "$archive_file" -C "$project_root" .
        fi
    else
        if [[ -n "$tar_option" ]]; then
            tar $tar_option -df "$archive_file" -C "$(dirname "$project_root")" "$project_name"
        else
            tar -df "$archive_file" -C "$(dirname "$project_root")" "$project_name"
        fi
    fi
}

# Compute and compare remote file hash to a local file's hash
# Usage: verify_remote_file_hash <local_file> <remote_server> <remote_path> <hash_algorithm>
verify_remote_file_hash() {
    local local_file="$1"
    local remote_server="$2"
    local remote_path="$3"
    local hash_algorithm="$4"

    if [[ ! -f "$local_file" ]]; then
        echo "Error: Local file not found for remote verify: $local_file" >&2
        return 1
    fi

    # Local hash
    case "$hash_algorithm" in
        sha256) local_hash=$(sha256sum "$local_file" | awk '{print $1}') ;;
        sha1) local_hash=$(sha1sum "$local_file" | awk '{print $1}') ;;
        md5) local_hash=$(md5sum "$local_file" | awk '{print $1}') ;;
        *) echo "Unknown hash algorithm: $hash_algorithm" >&2; return 1 ;;
    esac

    local base_name
    base_name="$(basename "$local_file")"

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

    if [[ -z "$remote_hash" ]]; then
        echo "Error: Remote hash could not be computed" >&2
        return 1
    fi

    if [[ "$local_hash" == "$remote_hash" ]]; then
        echo "Remote verify OK ($hash_algorithm): $remote_hash"
        return 0
    else
        echo "Remote verify FAILED" >&2
        echo "Local:  $local_hash" >&2
        echo "Remote: $remote_hash" >&2
        return 1
    fi
}

# Verify a mirror (rsync) by running a checksum dry-run
# Uses RSYNC_EXCLUDES from the current config context.
verify_mirror_integrity() {
    local source_dir="$1"
    local dest_dir="$2"

    if [[ ! -d "$dest_dir" ]]; then
        echo "Error: Destination mirror not found: $dest_dir" >&2
        return 1
    fi

    local args=("-rcn" "--delete" "-l")
    for exclude in "${RSYNC_EXCLUDES[@]}"; do
        if [[ "$exclude" == --exclude* ]]; then
            args+=("$exclude")
        fi
    done

    echo "Verifying mirror integrity (checksum dry-run)..."
    if diffout=$(rsync "${args[@]}" "$source_dir/" "$dest_dir/" 2>&1) && [[ -z "$diffout" ]]; then
        echo "Mirror verified: no differences"
        return 0
    else
        echo "$diffout"
        echo "Mirror verify FAILED: differences detected" >&2
        return 1
    fi
}

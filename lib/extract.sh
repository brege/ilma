#!/bin/bash

if [[ -z "${ILMA_DIR:-}" ]]; then
    echo "Error: ILMA_DIR must be set before sourcing lib/extract.sh" >&2
    exit 1
fi

source "$ILMA_DIR/lib/deps/compression.sh"

resolve_archive_target_directory() {
    local archive_file="$1"
    local explicit_target="${2:-}"

    if [[ -n "$explicit_target" ]]; then
        echo "$explicit_target"
        return
    fi

    local archive_base
    archive_base="$(basename "$archive_file")"

    if [[ "$archive_base" =~ \.[^.]+\.tar\. ]]; then
        local target_directory="$archive_base"
        target_directory="${target_directory%.tar.zst}"
        target_directory="${target_directory%.tar.gz}"
        target_directory="${target_directory%.tar.bz2}"
        target_directory="${target_directory%.tar.xz}"
        target_directory="${target_directory%.tar}"
        target_directory="${target_directory%.tgz}"
        target_directory="${target_directory%.tbz2}"
        target_directory="${target_directory%.txz}"
        target_directory="${target_directory%.gpg}"
        echo "$target_directory"
    else
        echo "${archive_base%%.*}"
    fi
}

validate_archive_paths_safe() {
    local archive_file="$1"
    local tar_option
    tar_option=$(get_tar_option "$(get_compression_type_from_file "$archive_file")")

    if [[ -n "$tar_option" ]]; then
        if tar $tar_option -tf "$archive_file" | LC_ALL=C grep -E '(^/|(^|/)\.\.(\/|$))' -q; then
            return 1
        fi
    else
        if tar -tf "$archive_file" | LC_ALL=C grep -E '(^/|(^|/)\.\.(\/|$))' -q; then
            return 1
        fi
    fi
    return 0
}

extract_archive_safely() {
    local archive_file="$1"
    local force_flag="${2:-false}"
    local target_directory="$3"

    if [[ ! -f "$archive_file" ]]; then
        echo "Error: Archive file does not exist: $archive_file" >&2
        return 1
    fi

    if ! is_archive "$archive_file"; then
        echo "Error: File is not a recognized archive: $archive_file" >&2
        return 1
    fi

    if [[ "$target_directory" == "/" ]]; then
        echo "Error: Refusing to extract into '/'" >&2
        return 1
    fi

    if ! validate_archive_paths_safe "$archive_file"; then
        echo "Error: Unsafe archive entries detected (absolute paths or ..)" >&2
        return 1
    fi

    if [[ -e "$target_directory" ]]; then
        if [[ "$force_flag" == "true" ]]; then
            if [[ -L "$target_directory" ]]; then
                echo "Error: Refusing to remove symlink target: $target_directory" >&2
                return 1
            fi
            rm -rf "$target_directory"
        else
            echo "Error: Target directory already exists: $target_directory" >&2
            echo "Use --force to replace, or --target to specify different location"
            return 1
        fi
    fi

    mkdir -p "$target_directory"

    local tar_option
    tar_option=$(get_tar_option "$(get_compression_type_from_file "$archive_file")")

    echo "Safely extracting $archive_file to $target_directory/"

    if [[ -n "$tar_option" ]]; then
        if tar $tar_option -xf "$archive_file" -C "$target_directory"; then
            echo "Archive extracted successfully to: $target_directory/"
            return 0
        fi
    else
        if tar -xf "$archive_file" -C "$target_directory"; then
            echo "Archive extracted successfully to: $target_directory/"
            return 0
        fi
    fi

    echo "Extraction failed"
    rmdir "$target_directory" 2>/dev/null
    return 1
}

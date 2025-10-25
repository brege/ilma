#!/bin/bash
# lib/validation/manifests.sh - sanity-check remote node manifests

set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ILMA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
DEFAULT_NODE_DIR="$ILMA_DIR/nodes"

source "$ILMA_DIR/commands/remote.sh"

print_section() {
    echo "SECTION:Remote Node Manifests"
}

collect_targets() {
    local -n _collector=$1
    shift

    if [[ $# -eq 0 ]]; then
        if [[ -d "$DEFAULT_NODE_DIR" ]]; then
            _collector+=("$DEFAULT_NODE_DIR")
        else
            return 0
        fi
    else
        _collector+=("$@")
    fi
}

enumerate_files() {
    local path="$1"
    local -n _files_ref=$2
    path="${path/#\~/$HOME}"

    if [[ -d "$path" ]]; then
        while IFS= read -r -d '' candidate; do
            _files_ref+=("$candidate")
        done < <(find "$path" -type f \( -name '*.ini' -o -name '*.conf' \) -print0 | sort -z)
    elif [[ -f "$path" ]]; then
        _files_ref+=("$path")
    else
        echo "WARN:Missing path:$path"
    fi
}

validate_manifest_file() {
    local file="$1"

    if ! try_parse_remote_job "$file"; then
        echo "FAIL:${file}:$REMOTE_JOB_PARSE_ERROR"
        return
    fi

    local manifest_temp normalized
    manifest_temp="$(mktemp)"
    normalized="$(mktemp)"

    printf '%s\n' "${REMOTE_JOB_MANIFEST[@]}" >"$manifest_temp"
    normalize_manifest_for_rsync "$manifest_temp" "$normalized"

    local mode_summary="${REMOTE_JOB_MODE:-backup}"
    local remote="${REMOTE_JOB_REMOTE}"
    local line_count="${#REMOTE_JOB_MANIFEST[@]}"
    echo "PASS:${file}:remote=${remote} mode=${mode_summary} lines=${line_count}"
    echo "INFO:Normalized manifest:${file}"
    sed 's/^/  /' "$normalized"
    rm -f "$manifest_temp" "$normalized"
}

main() {
    print_section
    local -a supplied_paths=()
    collect_targets supplied_paths "$@"

    if [[ ${#supplied_paths[@]} -eq 0 ]]; then
        echo "INFO:No node manifests directory found (looked for $DEFAULT_NODE_DIR)"
        return 0
    fi

    local -a manifest_files=()
    local path
    for path in "${supplied_paths[@]}"; do
        enumerate_files "$path" manifest_files
    done

    if [[ ${#manifest_files[@]} -eq 0 ]]; then
        echo "INFO:No manifest files discovered under ${supplied_paths[*]}"
        return 0
    fi

    local file
    for file in "${manifest_files[@]}"; do
        validate_manifest_file "$file"
    done
}

main "$@"

#!/bin/bash
set -euo pipefail

initialize_paths() {
    if [[ -n "${ILMA_DIR:-}" ]]; then
        return
    fi

    local caller_source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local caller_path
    caller_path="$(readlink -f "$caller_source")"
    local commands_directory
    commands_directory="$(dirname "$caller_path")"
    ILMA_DIR="$(dirname "$commands_directory")"
}

command_name() {
    local caller_source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local caller_path
    caller_path="$(readlink -f "$caller_source")"
    local caller_file
    caller_file="$(basename "$caller_path")"
    echo "${caller_file%.sh}"
}

require_project_root() {
    local path_argument="${1:-}"

    if [[ -z "$path_argument" ]]; then
        path_argument="$(pwd)"
    fi

    local resolved_path
    resolved_path="$(realpath "$path_argument" 2>/dev/null)" || {
        echo "Error: Invalid path '$path_argument'" >&2
        exit 1
    }

    if [[ "$resolved_path" == "/" ]]; then
        echo "Error: Refusing to operate on '/'" >&2
        exit 1
    fi

    echo "$resolved_path"
}

dispatch() {
    local usage_function="$1"
    local main_function="$2"
    shift 2

    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        "$usage_function"
        exit 0
    fi

    "$main_function" "$@"
}

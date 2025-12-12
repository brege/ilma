#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh"
initialize_paths

source "$ILMA_DIR/lib/extract.sh"

force_option=false
target_directory_option=""
archive_path=""
positional_targets=()

extract_usage() {
    cat <<'EOF'
Usage: ilma extract [OPTIONS] <archive_file> [TARGET_DIR]

Safely extract archive to a contained directory (prevents tarbombs).

OPTIONS:
  --force            Replace existing target directory
  --target DIR       Extract to specific directory instead of derived name
  -h, --help         Show this help message
EOF
}

parse_extract_arguments() {
    force_option=false
    target_directory_option=""
    archive_path=""
    positional_targets=()

    while (( $# > 0 )); do
        case "$1" in
            --force)
                force_option=true
                shift
                ;;
            --target)
                if [[ -n "$target_directory_option" ]]; then
                    echo "Error: --target specified multiple times" >&2
                    exit 1
                fi
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --target requires a directory path" >&2
                    exit 1
                fi
                target_directory_option="$2"
                shift 2
                ;;
            -h|--help)
                extract_usage
                exit 0
                ;;
            --*)
                echo "Error: Unknown option '$1'" >&2
                exit 1
                ;;
            *)
                if [[ -z "$archive_path" ]]; then
                    archive_path="$1"
                else
                    positional_targets+=("$1")
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$archive_path" ]]; then
        echo "Error: No archive file specified for extraction" >&2
        exit 1
    fi

    if [[ ${#positional_targets[@]} -gt 1 ]]; then
        echo "Error: Too many positional arguments provided" >&2
        exit 1
    fi

    if [[ -n "$target_directory_option" && ${#positional_targets[@]} -gt 0 ]]; then
        echo "Error: Specify target directory with --target or positional argument, not both" >&2
        exit 1
    fi
}

do_extract() {
    local archive_file="$1"
    local force_flag="${2:-false}"
    local target_directory="${3:-}"

    if [[ -z "$archive_file" ]]; then
        echo "Error: No archive file specified for extraction" >&2
        return 1
    fi

    if [[ ! -f "$archive_file" ]]; then
        echo "Error: Archive file does not exist: $archive_file" >&2
        return 1
    fi

    local resolved_target
    resolved_target="$(resolve_archive_target_directory "$archive_file" "$target_directory")"

    if extract_archive_safely "$archive_file" "$force_flag" "$resolved_target"; then
        echo "Contents:"
        ls -la "$resolved_target/"
        return 0
    else
        return 1
    fi
}

extract_main() {
    parse_extract_arguments "$@"

    if [[ "$archive_path" == "/" ]]; then
        echo "Error: Invalid path '/'" >&2
        exit 1
    fi

    if [[ ! -f "$archive_path" ]]; then
        echo "Error: Archive file does not exist: $archive_path" >&2
        exit 1
    fi

    local absolute_archive
    absolute_archive="$(realpath "$archive_path")"

    local target_directory_value="$target_directory_option"
    if [[ -z "$target_directory_value" && ${#positional_targets[@]} -eq 1 ]]; then
        target_directory_value="${positional_targets[0]}"
    fi

    if [[ -n "$target_directory_value" ]]; then
        target_directory_value="$(realpath -m "$target_directory_value")"
    fi

    local force_flag="false"
    if [[ "$force_option" == "true" ]]; then
        force_flag="true"
    fi

    do_extract "$absolute_archive" "$force_flag" "$target_directory_value"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dispatch extract_usage extract_main "$@"
fi

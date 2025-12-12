#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_template.sh"
template_initialize_paths

source "$ILMA_DIR/lib/deps/gpg.sh"
source "$ILMA_DIR/lib/extract.sh"

no_extract_option=false
force_option=false
target_directory_option=""
input_path=""

decrypt_usage() {
    cat <<'EOF'
Usage: ilma decrypt [OPTIONS] <encrypted_file>

Decrypt a GPG-encrypted file and optionally extract if it is an archive.

OPTIONS:
  --no-extract       Decrypt only, do not extract archive
  --force            Replace existing target directory when extracting
  --target DIR       Extract to specific directory instead of derived name
  -h, --help         Show this help message
EOF
}

parse_decrypt_arguments() {
    no_extract_option=false
    force_option=false
    target_directory_option=""
    input_path=""

    while (( $# > 0 )); do
        case "$1" in
            --no-extract)
                no_extract_option=true
                shift
                ;;
            --force)
                force_option=true
                shift
                ;;
            --target)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --target requires a directory path" >&2
                    exit 1
                fi
                target_directory_option="$2"
                shift 2
                ;;
            -h|--help)
                decrypt_usage
                exit 0
                ;;
            --*)
                echo "Error: Unknown option '$1'" >&2
                exit 1
                ;;
            *)
                if [[ -z "$input_path" ]]; then
                    input_path="$1"
                else
                    echo "Error: Too many arguments provided" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$input_path" ]]; then
        echo "Error: No input file specified for decryption" >&2
        exit 1
    fi
}

# Decrypt and optionally extract a GPG-encrypted file
do_decrypt() {
    local input_file="$1"
    local no_extract_flag="${2:-false}"
    local force_flag="${3:-false}"
    local target_directory="${4:-}"

    if [[ -z "$input_file" ]]; then
        echo "Error: No input file specified for decryption" >&2
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        echo "Error: Input file does not exist: $input_file" >&2
        return 1
    fi

    local output_file
    output_file="$input_file"

    if [[ "$input_file" =~ \.gpg$ ]]; then
        output_file="${input_file%.gpg}"
        if ! decrypt_file "$input_file" "$output_file"; then
            return 1
        fi
    fi

    if [[ "$no_extract_flag" == "true" ]]; then
        echo "Decryption complete: $output_file"
        return 0
    fi

    if ! is_archive "$output_file"; then
        echo "Decryption complete: $output_file"
        return 0
    fi

    if extract_decrypted_archive "$output_file" "$force_flag" "$target_directory"; then
        echo "Decryption and extraction complete: $(basename "$output_file" .tar.*)"
        return 0
    else
        return 1
    fi
}

extract_decrypted_archive() {
    local archive_file="$1"
    local force_flag="${2:-false}"
    local target_directory="${3:-}"

    local resolved_target
    resolved_target="$(resolve_archive_target_directory "$archive_file" "$target_directory")"

    extract_archive_safely "$archive_file" "$force_flag" "$resolved_target"
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

decrypt_main() {
    parse_decrypt_arguments "$@"

    if [[ "$input_path" == "/" ]]; then
        echo "Error: Invalid path '/'" >&2
        exit 1
    fi

    if [[ ! -f "$input_path" ]]; then
        echo "Error: Input file does not exist: $input_path" >&2
        exit 1
    fi

    local absolute_input
    absolute_input="$(realpath "$input_path")"

    local target_directory_value="$target_directory_option"
    if [[ -n "$target_directory_value" ]]; then
        target_directory_value="$(realpath -m "$target_directory_value")"
    fi

    local no_extract_flag="false"
    if [[ "$no_extract_option" == "true" ]]; then
        no_extract_flag="true"
    fi

    local force_flag="false"
    if [[ "$force_option" == "true" ]]; then
        force_flag="true"
    fi

    do_decrypt "$absolute_input" "$no_extract_flag" "$force_flag" "$target_directory_value"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    template_dispatch decrypt_usage decrypt_main "$@"
fi

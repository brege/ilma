#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_template.sh"
template_initialize_paths

source "$ILMA_DIR/lib/functions.sh"
source "$ILMA_DIR/lib/deps/compression.sh"
source "$ILMA_DIR/lib/deps/rsync.sh"
source "$ILMA_DIR/lib/deps/gpg.sh"
source "$ILMA_DIR/commands/config.sh"
source "$ILMA_DIR/lib/backup/archive.sh"
source "$ILMA_DIR/lib/backup/encrypt.sh"
source "$ILMA_DIR/lib/backup/remote.sh"
source "$ILMA_DIR/lib/singles.sh"
source "$ILMA_DIR/lib/validation/verify.sh"

backup_requested=false
backup_output=""
archive_requested=false
archive_output=""
encrypt_requested=false
encrypt_output=""
remote_target=""
type_name=""
target_directory=""
custom_basename=""
verify_option=""
timestamp_mode=false
config_only=false
positional_arguments=()

backup_usage() {
    cat <<'EOF'
Usage: backup.sh [OPTIONS] [PROJECT_PATH] [ADDITIONAL_PATHS...]

Create backups, archives, and encrypted archives for a project.

OPTIONS:
  -b, --backup [OUTPUT_PATH]     Create backup directory (explicit)
  -a, --archive [OUTPUT_PATH]    Create compressed archive only
  -e, --encrypt [OUTPUT_PATH]    Create encrypted archive only
  -r, --remote SERVER:/PATH      Sync directly to remote server
  --type TYPE                    Project type configuration
  --target DIR                   Output directory for generated artifacts
  --basename NAME                Custom base filename for archives
  --verify                       Verify outputs (archives)
  --timestamp                    Append timestamp to archive filename
  --config                       Show resolved configuration and exit
  -h, --help                     Show this help message

ARGUMENTS:
  PROJECT_PATH                   Project directory or file (default: current directory)
  ADDITIONAL_PATHS               Extra roots for multi-origin archive/encrypt

Default behavior runs a full backup when no operation flags are provided.
EOF
}

resolve_base_dir() {
    local base_dir="$1"
    local project_root="$2"
    local project_name="$3"
    local suffix="$4"

    if [[ -z "$base_dir" || "$base_dir" == ".." ]]; then
        echo "$(dirname "$project_root")/${project_name}${suffix}"
    elif [[ "$base_dir" == "." ]]; then
        echo "$project_root/${project_name}${suffix}"
    elif [[ "$base_dir" == /* ]]; then
        echo "${base_dir/#\~/$HOME}/${project_name}${suffix}"
    else
        echo "$project_root/$base_dir/${project_name}${suffix}"
    fi
}

resolve_backup_dir_with_deduplication() {
    local base_path="$1"
    local naming_strategy="${VERSIONING:-timestamp}"

    if [[ ! -d "$base_path" ]]; then
        echo "$base_path"
        return
    fi

    case "$naming_strategy" in
        "timestamp")
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            echo "${base_path%.bak}-${timestamp}.bak"
            ;;
        "numbered")
            local counter=1
            local numbered_path="${base_path%.bak}.${counter}.bak"
            while [[ -d "$numbered_path" ]]; do
                ((counter++))
                numbered_path="${base_path%.bak}.${counter}.bak"
            done
            echo "$numbered_path"
            ;;
        "overwrite")
            echo "$base_path"
            ;;
        *)
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            echo "${base_path%.bak}-${timestamp}.bak"
            ;;
    esac
}

do_backup() {
    local project_root="$1"
    if [[ -z "$project_root" || "$project_root" == "/" || ! -d "$project_root" ]]; then
        echo "Error: Invalid project path '$project_root'" >&2
        return 1
    fi
    local project_name
    project_name="$(basename "$project_root")"

    echo "Backing up project: $project_name"
    echo "Source: $project_root"

    local base_backup_path
    base_backup_path=$(resolve_base_dir "$BACKUP_BASE_DIR" "$project_root" "$project_name" ".bak")
    MAIN_BACKUP_DIR=$(resolve_backup_dir_with_deduplication "$base_backup_path")

    echo "Step 1: Creating main full backup at '$MAIN_BACKUP_DIR'..."
    mkdir -p "$MAIN_BACKUP_DIR"
    BACKUP_EXCLUDES=()

    if [[ "$MAIN_BACKUP_DIR" == "$project_root"/* ]]; then
        local backup_basename
        backup_basename="$(basename "$MAIN_BACKUP_DIR")"
        BACKUP_EXCLUDES+=(--exclude "$backup_basename/")
    fi
    local -a backup_rsync_args=()
    ilma_append_rsync_preserve_args backup_rsync_args
    backup_rsync_args+=(--delete --delete-delay --info=progress2)
    smart_copy "$project_root" "$MAIN_BACKUP_DIR" "${backup_rsync_args[@]}" "${BACKUP_EXCLUDES[@]}"
    echo "Main backup complete."

}

parse_backup_arguments() {
    backup_requested=false
    backup_output=""
    archive_requested=false
    archive_output=""
    encrypt_requested=false
    encrypt_output=""
    remote_target=""
    type_name=""
    target_directory=""
    custom_basename=""
    verify_option=""
    timestamp_mode=false
    config_only=false
    positional_arguments=()

    local expanded_arguments=()
    for argument in "$@"; do
        case "$argument" in
            -a) expanded_arguments+=(--archive) ;;
            -b) expanded_arguments+=(--backup) ;;
            -e) expanded_arguments+=(--encrypt) ;;
            -r) expanded_arguments+=(--remote) ;;
            -*)
                if [[ "$argument" =~ ^-[abe]{2,}$ ]]; then
                    local combined_flags="${argument#-}"
                    local index
                    for ((index=0; index<${#combined_flags}; index++)); do
                        case "${combined_flags:index:1}" in
                            a) expanded_arguments+=(--archive) ;;
                            b) expanded_arguments+=(--backup) ;;
                            e) expanded_arguments+=(--encrypt) ;;
                        esac
                    done
                else
                    expanded_arguments+=("$argument")
                fi
                ;;
            *)
                expanded_arguments+=("$argument")
                ;;
        esac
    done

    set -- "${expanded_arguments[@]}"

    while (( $# > 0 )); do
        case "$1" in
            --backup|-b)
                backup_requested=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" && "${2}" =~ \.bak$ ]]; then
                    backup_output="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --archive|-a)
                archive_requested=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" && "${2}" =~ \.(tar\.|tgz|tbz2|txz).*$ ]]; then
                    archive_output="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --encrypt|-e)
                encrypt_requested=true
                if [[ -n "${2:-}" && "${2:0:1}" != "-" && "${2}" =~ \.gpg$ ]]; then
                    encrypt_output="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --remote|-r)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --remote requires SERVER:/PATH argument" >&2
                    exit 1
                fi
                remote_target="$2"
                shift 2
                ;;
            --type)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --type requires an argument" >&2
                    exit 1
                fi
                if [[ -n "$type_name" ]]; then
                    type_name="${type_name}|${2}"
                else
                    type_name="$2"
                fi
                shift 2
                ;;
            --verify)
                verify_option="true"
                shift
                ;;
            --timestamp)
                timestamp_mode=true
                shift
                ;;
            --target)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --target requires a directory path" >&2
                    exit 1
                fi
                target_directory="$2"
                shift 2
                ;;
            --basename)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --basename requires a filename" >&2
                    exit 1
                fi
                custom_basename="$2"
                shift 2
                ;;
            --config)
                config_only=true
                shift
                ;;
            --help|-h)
                backup_usage
                exit 0
                ;;
            --*)
                echo "Error: Unknown option '$1'" >&2
                exit 1
                ;;
            *)
                positional_arguments+=("$1")
                shift
                ;;
        esac
    done
}

handle_timestamp_mode() {
    local target_path="$1"
    if [[ "$timestamp_mode" != "true" ]]; then
        return
    fi

    if [[ ! -f "$target_path" ]]; then
        echo "Error: --timestamp requires a file path" >&2
        exit 1
    fi

    local file="$target_path"
    local base
    local extension
    if [[ "$file" =~ ^(.*)\.tar\.(.*)$ ]]; then
        base="${BASH_REMATCH[1]}"
        extension="tar.${BASH_REMATCH[2]}"
    elif [[ "$file" =~ \.(tgz|tbz2|txz)$ ]]; then
        base="${file%.*}"
        extension="${file##*.}"
    else
        echo "Error: Not an archive file" >&2
        exit 1
    fi

    local timestamp
    timestamp="$(date -r "$file" +%Y%m%d-%H%M%S)"
    local new_file="${base}-${timestamp}.${extension}"
    mv "$file" "$new_file"
    echo "Renamed: $file -> $new_file"
    exit 0
}

backup_main() {
    parse_backup_arguments "$@"

    local project_input="${positional_arguments[0]:-}"
    local project_root
    project_root="$(template_require_project_root "$project_input")"

    handle_timestamp_mode "$project_root"

    local additional_paths=()
    if [[ ${#positional_arguments[@]} -gt 1 ]]; then
        local index
        for ((index=1; index<${#positional_arguments[@]}; index++)); do
            local resolved_path
            resolved_path="$(realpath "${positional_arguments[$index]}" 2>/dev/null)" || {
                echo "Error: Invalid path '${positional_arguments[$index]}'" >&2
                exit 1
            }
            if [[ "$resolved_path" == "/" ]]; then
                echo "Error: Refusing to operate on '/'" >&2
                exit 1
            fi
            additional_paths+=("$resolved_path")
        done
    fi

    if [[ ! -d "$project_root" ]]; then
        if [[ -f "$project_root" ]]; then
            local single_file_path="$project_root"
            project_root="$(dirname "$project_root")"

            load_config "$project_root" "$type_name"
            if [[ -z "$verify_option" ]]; then
                if [[ "${VERIFY:-}" == "true" || "${VERIFY_DEFAULT:-false}" == "true" ]]; then
                    verify_option="true"
                fi
            fi
            if [[ "$config_only" == "true" ]]; then
                show_config "$project_root"
                exit 0
            fi

            if [[ "$encrypt_requested" == "true" ]]; then
                if [[ -z "$GPG_KEY_ID" ]]; then
                    echo "Error: GPG key not configured. Set GPG_KEY_ID in config." >&2
                    exit 1
                fi
                do_single_file_encryption "$single_file_path"
                exit 0
            fi

            do_single_file_backup "$single_file_path"
            exit 0
        fi

        echo "Error: Directory or file does not exist: $project_root" >&2
        exit 1
    fi

    load_config "$project_root" "$type_name"

    if [[ -z "$verify_option" ]]; then
        if [[ "${VERIFY:-}" == "true" || "${VERIFY_DEFAULT:-false}" == "true" ]]; then
            verify_option="true"
        fi
    fi

    if [[ "$config_only" == "true" ]]; then
        show_config "$project_root"
        exit 0
    fi

    local operations_performed=false

    if [[ "$backup_requested" == "true" ]]; then
        if [[ -n "$target_directory" ]]; then
            local original_backup_base_dir="$BACKUP_BASE_DIR"
            BACKUP_BASE_DIR="$target_directory"
            do_backup "$project_root"
            BACKUP_BASE_DIR="$original_backup_base_dir"
        else
            do_backup "$project_root"
        fi
        operations_performed=true
    fi

    if [[ "$archive_requested" == "true" ]]; then
        local output_path="$archive_output"

        if [[ ${#additional_paths[@]} -gt 0 ]]; then
            local all_paths=("$project_root" "${additional_paths[@]}")
            if [[ -z "$output_path" ]]; then
                local archive_basename
                if [[ -n "$custom_basename" ]]; then
                    archive_basename="$custom_basename"
                else
                    local timestamp
                    timestamp="$(date '+%Y%m%d-%H%M%S')"
                    archive_basename="multi-origin-${timestamp}"
                fi
                if [[ -n "$target_directory" ]]; then
                    output_path="$target_directory/${archive_basename}$(get_archive_extension "$COMPRESSION_TYPE")"
                else
                    output_path="./${archive_basename}$(get_archive_extension "$COMPRESSION_TYPE")"
                fi
            fi
            create_multi_origin_archive "$output_path" "${all_paths[@]}"
        else
            if [[ -z "$output_path" ]]; then
                if [[ -n "$custom_basename" || -n "$target_directory" ]]; then
                    local archive_basename
                    if [[ -n "$custom_basename" ]]; then
                        archive_basename="$custom_basename"
                    else
                        archive_basename="$(basename "$project_root")"
                    fi
                    local base_output_path
                    if [[ -n "$target_directory" ]]; then
                        base_output_path="$target_directory/${archive_basename}$(get_archive_extension "$COMPRESSION_TYPE")"
                    else
                        base_output_path="$(dirname "$project_root")/${archive_basename}$(get_archive_extension "$COMPRESSION_TYPE")"
                    fi
                    if [[ "$ARCHIVE_VERSIONING" == "force_timestamp" ]]; then
                        local timestamp
                        timestamp="$(date '+%Y%m%d-%H%M%S')"
                        local archive_extension
                        archive_extension="$(get_archive_extension "$COMPRESSION_TYPE")"
                        local basename_path="${base_output_path%"$archive_extension"}"
                        output_path="${basename_path}-${timestamp}${archive_extension}"
                    else
                        output_path="$(resolve_archive_path_with_deduplication "$base_output_path")"
                    fi
                else
                    output_path=""
                fi
            fi
            create_archive_only "$project_root" "$output_path"
        fi

        operations_performed=true

        if [[ -n "$remote_target" ]]; then
            local archive_file="$output_path"
            if [[ -z "$archive_file" || ! -f "$archive_file" ]]; then
                local parent_dir
                parent_dir="$(dirname "$project_root")"
                local base_name
                base_name="$(basename "$project_root")"
                local extension
                extension="$(get_archive_extension "$COMPRESSION_TYPE")"
                mapfile -t candidates < <(ls -1t "$parent_dir"/"$base_name"-*"$extension" 2>/dev/null || true)
                if [[ ${#candidates[@]} -gt 0 ]]; then
                    archive_file="${candidates[0]}"
                else
                    archive_file="$parent_dir/$base_name$extension"
                fi
            fi
            sync_archive_to_remote "$archive_file" "$remote_target"
        fi

        if [[ "$verify_option" == "true" ]]; then
            local final_archive="$output_path"
            if [[ -z "$final_archive" ]]; then
                local parent_dir
                parent_dir="$(dirname "$project_root")"
                local base_name
                base_name="$(basename "$project_root")"
                local extension
                extension="$(get_archive_extension "$COMPRESSION_TYPE")"
                mapfile -t candidates < <(ls -1t "$parent_dir"/"$base_name"-*"$extension" 2>/dev/null || true)
                if [[ ${#candidates[@]} -gt 0 ]]; then
                    final_archive="${candidates[0]}"
                fi
            fi
            if [[ -n "$final_archive" && -f "$final_archive" ]]; then
                verify_archive_against_dir "$final_archive" "$project_root" "$(basename "$project_root")" || true
                if [[ -n "$remote_target" ]]; then
                    local remote_server="${remote_target%%:*}"
                    local remote_path="${remote_target#*:}"
                    : "${HASH_ALGORITHM:=sha256}"
                    verify_remote_file_hash "$final_archive" "$remote_server" "$remote_path" "$HASH_ALGORITHM" || true
                fi
            fi
        fi
    fi

    if [[ "$encrypt_requested" == "true" ]]; then
        local output_path="$encrypt_output"

        if [[ ${#additional_paths[@]} -gt 0 ]]; then
            local all_paths=("$project_root" "${additional_paths[@]}")
            if [[ -z "$output_path" ]]; then
                local encrypt_basename
                if [[ -n "$custom_basename" ]]; then
                    encrypt_basename="$custom_basename"
                else
                    local timestamp
                    timestamp="$(date '+%Y%m%d-%H%M%S')"
                    encrypt_basename="multi-origin-${timestamp}"
                fi
                if [[ -n "$target_directory" ]]; then
                    output_path="$target_directory/${encrypt_basename}$(get_archive_extension "$COMPRESSION_TYPE")${GPG_OUTPUT_EXTENSION:-.gpg}"
                else
                    output_path="./${encrypt_basename}$(get_archive_extension "$COMPRESSION_TYPE")${GPG_OUTPUT_EXTENSION:-.gpg}"
                fi
            fi
            create_multi_origin_gpg "$output_path" "${all_paths[@]}"
        else
            if [[ -z "$output_path" ]]; then
                local encrypt_basename
                if [[ -n "$custom_basename" ]]; then
                    encrypt_basename="$custom_basename"
                else
                    encrypt_basename="$(basename "$project_root")"
                fi
                if [[ -n "$target_directory" ]]; then
                    output_path="$target_directory/${encrypt_basename}$(get_archive_extension "$COMPRESSION_TYPE")${GPG_OUTPUT_EXTENSION:-.gpg}"
                else
                    output_path="$(dirname "$project_root")/${encrypt_basename}$(get_archive_extension "$COMPRESSION_TYPE")${GPG_OUTPUT_EXTENSION:-.gpg}"
                fi
            fi
            create_gpg "$project_root" "$output_path"
        fi

        operations_performed=true

        if [[ -n "$remote_target" ]]; then
            local encrypted_file="$output_path"
            if [[ -z "$encrypted_file" || ! -f "$encrypted_file" ]]; then
                local parent_dir
                parent_dir="$(dirname "$project_root")"
                local base_name
                base_name="$(basename "$project_root")"
                local archive_extension
                archive_extension="$(get_archive_extension "$COMPRESSION_TYPE")"
                local gpg_extension="${GPG_OUTPUT_EXTENSION:-.gpg}"
                mapfile -t candidates < <(ls -1t "$parent_dir"/"$base_name"-*"$archive_extension""$gpg_extension" 2>/dev/null || true)
                if [[ ${#candidates[@]} -gt 0 ]]; then
                    encrypted_file="${candidates[0]}"
                else
                    encrypted_file="$parent_dir/$base_name$archive_extension$gpg_extension"
                fi
            fi
            sync_archive_to_remote "$encrypted_file" "$remote_target"
        fi

        if [[ "$verify_option" == "true" ]]; then
            local final_encrypted="$output_path"
            if [[ -n "$final_encrypted" && -f "$final_encrypted" ]]; then
                echo "Local encrypted hash (sha256): $(sha256sum "$final_encrypted" | awk '{print $1}')"
            fi
            if [[ -n "$remote_target" && -n "$final_encrypted" ]]; then
                local remote_server="${remote_target%%:*}"
                local remote_path="${remote_target#*:}"
                : "${HASH_ALGORITHM:=sha256}"
                verify_remote_file_hash "$final_encrypted" "$remote_server" "$remote_path" "$HASH_ALGORITHM" || true
            fi
        fi
    fi

    if [[ -n "$remote_target" && "$archive_requested" == "false" && "$encrypt_requested" == "false" ]]; then
        sync_to_remote "$project_root" "$remote_target"
        operations_performed=true
    fi

    if [[ "$operations_performed" == "false" ]]; then
        do_backup "$project_root"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    template_dispatch backup_usage backup_main "$@"
fi

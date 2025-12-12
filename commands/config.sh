#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_template.sh"
template_initialize_paths

source "$ILMA_DIR/lib/configs.sh"

type_name=""
project_path=""

# Load INI configuration file
load_ini_config() {
    local ini_file="$1"
    local section=""

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Section headers
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key-value pairs
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]// /}"
            local value="${BASH_REMATCH[2]# }"

            # Skip empty values (allows overriding with later non-empty values)
            [[ -z "$value" ]] && continue

            case "$section.$key" in
                compression.type) COMPRESSION_TYPE="$value" ;;
                compression.level) COMPRESSION_LEVEL="$value" ;;
                backup.create_compressed_archive) CREATE_COMPRESSED_ARCHIVE="$value" ;;
                backup.max_archives) MAX_ARCHIVES="$value" ;;
                backup.naming) VERSIONING="$value" ;;
                backup.archive_naming) ARCHIVE_VERSIONING="$value" ;;
                backup.encrypt_naming) ENCRYPT_VERSIONING="$value" ;;
                backup.backup_base_dir) BACKUP_BASE_DIR="$value" ;;
                backup.archive_base_dir) ARCHIVE_BASE_DIR="$value" ;;
                rsync.remote_server) REMOTE_SERVER="$value" ;;
                rsync.remote_path) REMOTE_PATH="$value" ;;
                rsync.cleanup_after_transfer) CLEANUP_AFTER_TRANSFER="$value" ;;
                hash.algorithm) HASH_ALGORITHM="$value" ;;
                gpg.key_id) GPG_KEY_ID="$value" ;;
                gpg.output_extension) GPG_OUTPUT_EXTENSION="$value" ;;
                verify.enabled) VERIFY_DEFAULT="$value" ;;
            esac
        fi
    done < "$ini_file"
}

load_config() {
    local project_root="$1"
    local type="${2:-}"

    # Set default configuration variables
    BACKUP_BASE_DIR=""
    ARCHIVE_BASE_DIR=""
    CREATE_COMPRESSED_ARCHIVE=false
    MAX_ARCHIVES=5
    VERSIONING="timestamp"
    ARCHIVE_VERSIONING="timestamp"
    ENCRYPT_VERSIONING="timestamp"
    EXTENSIONS=(md txt)
    RSYNC_EXCLUDES=()
    COMPRESSION_TYPE="zstd"
    COMPRESSION_LEVEL="3"
    REMOTE_SERVER=""
    REMOTE_PATH=""
    CLEANUP_AFTER_TRANSFER="false"
    HASH_ALGORITHM="sha256"
    GPG_KEY_ID=""
    GPG_OUTPUT_EXTENSION=".gpg"
    VERIFY_DEFAULT=false

    # Load central config.ini first
    CONFIG_FOUND=false
    local global_config_path=""
    if global_config_path="$(get_ilma_global_config_path)"; then
        load_ini_config "$global_config_path"
        CONFIG_FOUND=true
    fi

    # Load type-specific config if specified (for archive creation only)
    TYPE_CONFIG_LOADED=false
    if [[ -n "$type" ]]; then
        local type_config=""
        if type_config="$(resolve_ilma_type_config "$type")"; then
            source "$type_config"
            TYPE_CONFIG_LOADED=true
        else
            echo "Warning: Configuration type '$type' not found, using defaults" >&2
        fi
    fi

    # Load project-local configuration (enables full pipeline)
    if [[ -f "$project_root/.ilma.conf" ]]; then
        # First pass: check if PROJECT_TYPE is specified
        PROJECT_TYPE=""
        source "$project_root/.ilma.conf"

        # If PROJECT_TYPE is set, load that type config first
        if [[ -n "$PROJECT_TYPE" ]]; then
            local type_config=""
            if type_config="$(resolve_ilma_type_config "$PROJECT_TYPE")"; then
                source "$type_config"
            else
                echo "Warning: PROJECT_TYPE '$PROJECT_TYPE' not found in configured project directories" >&2
            fi

            # Second pass: re-source local config for overrides/appends
            source "$project_root/.ilma.conf"
        fi

        CONFIG_FOUND=true
    fi
}

# Handle special modes (archive flag, fallback, etc.)
handle_special_modes() {
    local archive_flag="$1"
    local project_root="$2"

    if [[ -n "$archive_flag" ]]; then
        # --archive mode: force archive creation
        RSYNC_EXCLUDES=()  # No exclusions - archive everything
        CREATE_COMPRESSED_ARCHIVE=true
        ARCHIVE_BASE_DIR="$(dirname "$archive_flag")"
        CONFIG_FOUND="false"  # Skip normal workflow
        echo "Archive mode: creating complete image at $archive_flag"
    elif [[ "$CONFIG_FOUND" == "false" ]]; then
        # Fallback/type-only mode: if no local config found, create simple archive in current directory
        # Keep type-specific exclusions if type config was loaded, otherwise use safe defaults
        if [[ "$TYPE_CONFIG_LOADED" == "false" ]]; then
            # SAFETY: Always exclude critical directories even in fallback mode
            RSYNC_EXCLUDES=(
                --exclude '.svn/'
                --exclude '.hg/'
                --exclude '.bzr/'
                --exclude '*.tar.*'
                --exclude '*.tar'
            )
        fi
        CREATE_COMPRESSED_ARCHIVE=true
        # Archive to parent directory by default (like tar stash behavior)
        ARCHIVE_BASE_DIR="$(dirname "$(realpath "$project_root")")"

        if [[ "$TYPE_CONFIG_LOADED" == "true" ]]; then
            echo "Type configuration loaded - creating archive in current directory"
        else
            echo "No configuration found - creating archive in current directory"
        fi
    fi
}

usage() {
    cat <<EOF
Usage: ilma config [PROJECT_PATH]

Display current configuration settings and resolved paths.

ARGUMENTS:
  PROJECT_PATH     Path to project directory (default: current directory)

OPTIONS:
  -h, --help       Show this help message

DESCRIPTION:
  Shows the effective configuration for a project, including:
  - Whether a local .ilma.conf file was found
  - Resolved backup and archive directory paths
  - Archive creation settings and limits
  - File extensions being tracked

  This is useful for troubleshooting configuration issues and
  understanding which settings will be applied during backup operations.

EXAMPLES:
  ilma config                     # Show config for current directory
  ilma config ~/my-project        # Show config for specific project

NOTES:
  - Configuration hierarchy: CLI flags > ~/.config/ilma/config.ini > defaults
  - Local .ilma.conf files override global settings
  - Use this to verify your configuration before running backups

EOF
    exit 0
}

# Show configuration (--config command)
show_config() {
    local project_root="$1"

    echo "Project: $project_root"
    echo "Config found: ${CONFIG_FOUND}"
    echo
    if [[ "$CONFIG_FOUND" == "true" ]]; then
        local backup_display
        if [[ -n "$BACKUP_BASE_DIR" ]]; then
            backup_display="$(realpath -m "${BACKUP_BASE_DIR/#\~/$HOME}")"
        else
            backup_display="(not set)"
        fi
        echo "Resolved paths:"
        echo "  BACKUP_BASE_DIR   = $backup_display"
        if [[ -n "$ARCHIVE_BASE_DIR" ]]; then
            echo "  ARCHIVE_BASE_DIR  = $(realpath -m "${ARCHIVE_BASE_DIR/#\~/$HOME}")"
        else
            echo "  ARCHIVE_BASE_DIR  = (not set)"
        fi
        echo
        echo "Settings:"
        echo "  CREATE_COMPRESSED_ARCHIVE = $CREATE_COMPRESSED_ARCHIVE"
        echo "  MAX_ARCHIVES             = $MAX_ARCHIVES"
        echo "  VERSIONING   = $VERSIONING"
        echo "  ARCHIVE_VERSIONING = $ARCHIVE_VERSIONING"
        echo "  ENCRYPT_VERSIONING = $ENCRYPT_VERSIONING"
        echo "  EXTENSIONS               = (${EXTENSIONS[*]})"
    else
        local fallback_archive_dir
        if [[ -n "$ARCHIVE_BASE_DIR" ]]; then
            fallback_archive_dir="$(realpath -m "${ARCHIVE_BASE_DIR/#\~/$HOME}")"
        else
            fallback_archive_dir="$(dirname "$project_root")"
        fi
        echo "Fallback mode - no configuration file found."
        echo "  ARCHIVE_BASE_DIR = $fallback_archive_dir"
    fi
}

parse_config_arguments() {
    type_name=""
    project_path=""

    while (( $# > 0 )); do
        case "$1" in
            --type)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --type requires an argument" >&2
                    exit 1
                fi
                type_name="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            --*)
                echo "Error: Unknown option '$1'" >&2
                exit 1
                ;;
            *)
                if [[ -z "$project_path" ]]; then
                    project_path="$1"
                elif [[ -z "$type_name" ]]; then
                    type_name="${type_name:-$1}"
                else
                    echo "Error: Too many positional arguments" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$project_path" ]]; then
        project_path="$(pwd)"
    fi
}

config_main() {
    parse_config_arguments "$@"
    local project_root
    project_root="$(template_require_project_root "$project_path")"
    load_config "$project_root" "$type_name"
    show_config "$project_root"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    template_dispatch usage config_main "$@"
fi

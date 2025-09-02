#!/bin/bash
# lib/config.sh - Configuration loading and management for ilma

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
                backup.backup_xdg_dirs) BACKUP_XDG_DIRS="$value" ;;
                backup.backup_base_dir) BACKUP_BASE_DIR="$value" ;;
                backup.archive_base_dir) ARCHIVE_BASE_DIR="$value" ;;
                backup.context_base_dir) CONTEXT_BASE_DIR="$value" ;;
                rsync.remote_server) REMOTE_SERVER="$value" ;;
                rsync.remote_path) REMOTE_PATH="$value" ;;
                rsync.cleanup_after_transfer) CLEANUP_AFTER_TRANSFER="$value" ;;
                hash.algorithm) HASH_ALGORITHM="$value" ;;
                gpg.key_id) GPG_KEY_ID="$value" ;;
                gpg.output_extension) GPG_OUTPUT_EXTENSION="$value" ;;
            esac
        fi
    done < "$ini_file"
}

# Load configuration with type support and fallback handling
load_config() {
    local project_root="$1"
    local type="${2:-}"

    # Set default configuration variables
    BACKUP_BASE_DIR="."
    ARCHIVE_BASE_DIR=""
    CONTEXT_BASE_DIR=""
    CREATE_COMPRESSED_ARCHIVE=false
    MAX_ARCHIVES=5
    BACKUP_XDG_DIRS=false
    XDG_PATHS=("$HOME/.config" "$HOME/.local/share" "$HOME/.cache")
    EXTENSIONS=(md txt)
    RSYNC_EXCLUDES=()
    CONTEXT_FILES=()
    TREE_EXCLUDES=""
    COMPRESSION_TYPE="zstd"
    COMPRESSION_LEVEL="3"
    REMOTE_SERVER=""
    REMOTE_PATH=""
    CLEANUP_AFTER_TRANSFER="false"
    HASH_ALGORITHM="sha256"
    GPG_KEY_ID=""
    GPG_OUTPUT_EXTENSION=".gpg"

    # Load central config.ini first
    ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
    if [[ -f "$ILMA_DIR/config.ini" ]]; then
        load_ini_config "$ILMA_DIR/config.ini"
    fi

    # Legacy configs removed - all defaults now in config.ini

    # Load type-specific config if specified (for archive creation only)
    TYPE_CONFIG_LOADED=false
    if [[ -n "$type" ]]; then
        local type_config="$ILMA_DIR/configs/${type}-project.ilma.conf"
        if [[ -f "$type_config" ]]; then
            source "$type_config"
            TYPE_CONFIG_LOADED=true
        elif [[ -f "$ILMA_DIR/configs/${type}.ilma.conf" ]]; then
            source "$ILMA_DIR/configs/${type}.ilma.conf"
            TYPE_CONFIG_LOADED=true
        else
            echo "Warning: Configuration type '$type' not found, using defaults" >&2
        fi
    fi

    # Load project-local configuration (enables full pipeline)
    CONFIG_FOUND=false
    for config_file in ".ilma.conf" ".archive.conf" ".backup.conf"; do
        if [[ -f "$project_root/$config_file" ]]; then
            # First pass: check if PROJECT_TYPE is specified
            PROJECT_TYPE=""
            source "$project_root/$config_file"

            # If PROJECT_TYPE is set, load that type config first
            if [[ -n "$PROJECT_TYPE" ]]; then
                local type_config="$ILMA_DIR/configs/${PROJECT_TYPE}-project.ilma.conf"
                if [[ -f "$type_config" ]]; then
                    source "$type_config"
                elif [[ -f "$ILMA_DIR/configs/${PROJECT_TYPE}.ilma.conf" ]]; then
                    source "$ILMA_DIR/configs/${PROJECT_TYPE}.ilma.conf"
                else
                    echo "Warning: PROJECT_TYPE '$PROJECT_TYPE' not found in configs/" >&2
                fi

                # Second pass: re-source local config for overrides/appends
                source "$project_root/$config_file"
            fi

            CONFIG_FOUND=true
            break
        fi
    done
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
        BACKUP_XDG_DIRS=false
        CONTEXT_BASE_DIR=""  # No context mirror
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
        BACKUP_XDG_DIRS=false
        CONTEXT_BASE_DIR=""  # No context mirror in fallback mode

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
  - Resolved backup, archive, and context directory paths
  - Archive creation settings and limits
  - File extensions being tracked
  - XDG directory backup settings

  This is useful for troubleshooting configuration issues and
  understanding which settings will be applied during backup operations.

EXAMPLES:
  ilma config                     # Show config for current directory
  ilma config ~/my-project        # Show config for specific project

NOTES:
  - Configuration hierarchy: CLI flags > ~/.config/oshea/config.yaml > defaults
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
        echo "Resolved paths:"
        echo "  BACKUP_BASE_DIR   = $(realpath "${BACKUP_BASE_DIR/#\~/$HOME}")"
        if [[ -n "$ARCHIVE_BASE_DIR" ]]; then
            echo "  ARCHIVE_BASE_DIR  = $(realpath "${ARCHIVE_BASE_DIR/#\~/$HOME}")"
        else
            echo "  ARCHIVE_BASE_DIR  = (not set)"
        fi
        if [[ -n "$CONTEXT_BASE_DIR" ]]; then
            echo "  CONTEXT_BASE_DIR  = $(realpath "${CONTEXT_BASE_DIR/#\~/$HOME}")"
        else
            echo "  CONTEXT_BASE_DIR  = (nested in backup)"
        fi
        echo
        echo "Settings:"
        echo "  CREATE_COMPRESSED_ARCHIVE = $CREATE_COMPRESSED_ARCHIVE"
        echo "  MAX_ARCHIVES             = $MAX_ARCHIVES"
        echo "  BACKUP_XDG_DIRS          = $BACKUP_XDG_DIRS"
        echo "  EXTENSIONS               = (${EXTENSIONS[*]})"
    else
        echo "Fallback mode - no configuration file found."
        echo "  ARCHIVE_BASE_DIR = $(realpath "${ARCHIVE_BASE_DIR/#\~/$HOME}")"
    fi
}

# If called directly as a command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle help flag
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat << 'EOF'
Usage: config.sh [PROJECT_PATH] [TYPE]

Standalone configuration tool - loads and displays project configuration.

Arguments:
  PROJECT_PATH    Path to project directory (default: current directory)
  TYPE            Project type for --type flag simulation

Examples:
  ./lib/config.sh /path/to/project
  ./lib/config.sh . python
  ./lib/config.sh /path/to/project bash

Shows resolved configuration including PROJECT_TYPE inheritance and all settings.
EOF
        exit 0
    fi

    PROJECT_ROOT="${1:-$(pwd)}"
    TYPE="${2:-}"

    load_config "$PROJECT_ROOT" "$TYPE"
    show_config "$PROJECT_ROOT"
fi
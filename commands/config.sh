#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh"
initialize_paths

source "$ILMA_DIR/lib/configs.sh"

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
  done <"$ini_file"
}

load_config() {
  local project_root="$1"

  # Set default configuration variables
  BACKUP_BASE_DIR=""
  ARCHIVE_BASE_DIR=""
  CREATE_COMPRESSED_ARCHIVE=false
  MAX_ARCHIVES=5
  VERSIONING="timestamp"
  ARCHIVE_VERSIONING="timestamp"
  ENCRYPT_VERSIONING="timestamp"
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

  # Load project-local configuration (enables full pipeline)
  if [[ -f "$project_root/.ilma.conf" ]]; then
    source "$project_root/.ilma.conf"

    CONFIG_FOUND=true
  fi
}

# Handle special modes (archive flag, fallback, etc.)
handle_special_modes() {
  local archive_flag="$1"
  local project_root="$2"

  if [[ -n "$archive_flag" ]]; then
    # --archive mode: force archive creation
    RSYNC_EXCLUDES=() # No exclusions - archive everything
    CREATE_COMPRESSED_ARCHIVE=true
    ARCHIVE_BASE_DIR="$(dirname "$archive_flag")"
    CONFIG_FOUND="false" # Skip normal workflow
    echo "Archive mode: creating complete image at $archive_flag"
  elif [[ "$CONFIG_FOUND" == "false" ]]; then
    # Fallback mode: if no local config found, create simple archive in current directory
    RSYNC_EXCLUDES=(
      --exclude '.svn/'
      --exclude '.hg/'
      --exclude '.bzr/'
      --exclude '*.tar.*'
      --exclude '*.tar'
    )
    CREATE_COMPRESSED_ARCHIVE=true
    # Archive to parent directory by default (like tar stash behavior)
    ARCHIVE_BASE_DIR="$(dirname "$(realpath "$project_root")")"

    echo "No configuration found - creating archive in current directory"
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
  project_path=""

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        usage
        ;;
      --*)
        echo "Error: Unknown option '$1'" >&2
        exit 1
        ;;
      *)
        if [[ -z "$project_path" ]]; then
          project_path="$1"
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
  project_root="$(require_project_root "$project_path")"
  load_config "$project_root"
  show_config "$project_root"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  dispatch usage config_main "$@"
fi

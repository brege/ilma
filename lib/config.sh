#!/bin/bash
# lib/config.sh - Configuration loading and management for ilma

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
    
    # Load default config first
    ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
    if [[ -f "$ILMA_DIR/configs/default.conf" ]]; then
        source "$ILMA_DIR/configs/default.conf"
    fi
    
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
            source "$project_root/$config_file"
            CONFIG_FOUND=true
            break
        fi
    done
}

# Handle special modes (archive flag, fallback, etc.)
handle_special_modes() {
    local archive_flag="$1"
    
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
        # Keep type-specific exclusions if type config was loaded, otherwise no exclusions
        if [[ "$TYPE_CONFIG_LOADED" == "false" ]]; then
            RSYNC_EXCLUDES=()  # No exclusions - archive everything
        fi
        CREATE_COMPRESSED_ARCHIVE=true
        ARCHIVE_BASE_DIR="$(pwd)"  # Explicit current working directory
        BACKUP_XDG_DIRS=false
        CONTEXT_BASE_DIR=""  # No context mirror in fallback mode
        
        if [[ "$TYPE_CONFIG_LOADED" == "true" ]]; then
            echo "Type configuration loaded - creating archive in current directory"
        else
            echo "No configuration found - creating archive in current directory"
        fi
    fi
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
    PROJECT_ROOT="${1:-$(pwd)}"
    TYPE="${2:-}"
    
    load_config "$PROJECT_ROOT" "$TYPE"
    show_config "$PROJECT_ROOT"
fi
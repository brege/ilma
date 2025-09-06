#!/bin/bash
# commands/backup.sh - Main backup functionality for ilma

# Source required functions
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "$ILMA_DIR/lib/functions.sh"
source "$ILMA_DIR/lib/deps/compression.sh"
source "$ILMA_DIR/lib/deps/rsync.sh"
source "$ILMA_DIR/lib/deps/gpg.sh"

# Unified path resolution for *_base_dir settings
resolve_base_dir() {
    local base_dir="$1"
    local project_root="$2"
    local project_name="$3"
    local suffix="$4"

    if [[ -z "$base_dir" || "$base_dir" == ".." ]]; then
        # Default: sibling to project
        echo "$(dirname "$project_root")/${project_name}${suffix}"
    elif [[ "$base_dir" == "." ]]; then
        # Inside target directory
        echo "$project_root/${project_name}${suffix}"
    elif [[ "$base_dir" == /* ]]; then
        # Absolute path
        echo "${base_dir/#\~/$HOME}/${project_name}${suffix}"
    else
        # Relative path - relative to project directory
        echo "$project_root/$base_dir/${project_name}${suffix}"
    fi
}

# Generate unique backup directory name with timestamp/numbering
resolve_backup_dir_with_deduplication() {
    local base_path="$1"
    local naming_strategy="${VERSIONING:-timestamp}"

    # If directory doesn't exist, use it as-is
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
            # Default to timestamp
            local timestamp
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            echo "${base_path%.bak}-${timestamp}.bak"
            ;;
    esac
}

# Main backup function
do_backup() {
    local project_root="$1"
    local project_name
    project_name="$(basename "$project_root")"

    echo "Backing up project: $project_name"
    echo "Source: $project_root"

    # Configuration should be loaded before calling this function
    # Variables expected: BACKUP_BASE_DIR, CONFIG_FOUND, etc.

    # Resolve backup directory path with deduplication
    local base_backup_path
    base_backup_path=$(resolve_base_dir "$BACKUP_BASE_DIR" "$project_root" "$project_name" ".bak")
    MAIN_BACKUP_DIR=$(resolve_backup_dir_with_deduplication "$base_backup_path")

    # Set context mirror location
    if [[ -n "$CONTEXT_BASE_DIR" ]]; then
        MIRROR_DIR=$(resolve_base_dir "$CONTEXT_BASE_DIR" "$project_root" "$project_name" ".context")
        MIRROR_DIR_BASENAME="$(basename "$MIRROR_DIR")"
    else
        # Default: nested in backup directory
        MIRROR_DIR_BASENAME="${project_name}.context"
        MIRROR_DIR="$MAIN_BACKUP_DIR/$MIRROR_DIR_BASENAME"
    fi

    # Always create backup directory
    {
        # --- Step 1: Main Full Backup ---
        echo "Step 1: Creating main full backup at '$MAIN_BACKUP_DIR'..."
        mkdir -p "$MAIN_BACKUP_DIR"
        # Exclude backup directory itself to prevent recursion
        BACKUP_EXCLUDES=(--exclude "$MIRROR_DIR_BASENAME/")

        # Check if backup directory is inside project directory
        if [[ "$MAIN_BACKUP_DIR" == "$project_root"/* ]]; then
            backup_basename="$(basename "$MAIN_BACKUP_DIR")"
            BACKUP_EXCLUDES+=(--exclude "$backup_basename/")
        fi

        rsync -av --delete \
             "${BACKUP_EXCLUDES[@]}" \
             "$project_root/" "$MAIN_BACKUP_DIR/"
        echo "Main backup complete."
    }

    # Only do XDG backup, context mirror, and stats in configured mode
    if [[ "$CONFIG_FOUND" == "true" ]]; then
        # --- Step 1a: Backup XDG directories if enabled ---
        if [[ "$BACKUP_XDG_DIRS" == "true" ]]; then
            echo "Step 1a: Backing up XDG directories..."
            XDG_BACKUP_DIR="$MAIN_BACKUP_DIR/xdg"
            mkdir -p "$XDG_BACKUP_DIR"

            for xdg_base in "${XDG_PATHS[@]}"; do
                # Expand tilde and check if project-specific directory exists
                xdg_expanded="${xdg_base/#\~/$HOME}"
                project_xdg_dir="$xdg_expanded/$project_name"

                if [[ -d "$project_xdg_dir" ]]; then
                    # Create relative path structure in backup
                    xdg_rel_path="${xdg_base#~/}"  # Remove ~/ prefix
                    backup_dest="$XDG_BACKUP_DIR/$xdg_rel_path"
                    mkdir -p "$backup_dest"

                    rsync -av "$project_xdg_dir/" "$backup_dest/$project_name/"
                    echo "  - Backed up $project_xdg_dir"
                fi
            done
            echo "XDG backup complete."
        fi

        echo

        # --- Step 2: Create Context Mirror ---
        echo "Step 2: Creating context mirror at '$MIRROR_DIR'..."
        mkdir -p "$MIRROR_DIR"

        # Add dynamic exclusions to the configured list
        DYNAMIC_EXCLUDES=(
            --exclude "$(basename "$MAIN_BACKUP_DIR")/"
        )

        # If using separate context directory, exclude it from backup
        if [[ -n "$CONTEXT_BASE_DIR" && "$CONTEXT_BASE_DIR" != "$BACKUP_BASE_DIR" ]]; then
            CONTEXT_BASE_BASENAME="$(basename "$CONTEXT_BASE_DIR")"
            if [[ "$project_root" == *"/$CONTEXT_BASE_BASENAME"* || "$project_root" == *"$CONTEXT_BASE_BASENAME" ]]; then
                DYNAMIC_EXCLUDES+=(--exclude "$(basename "$CONTEXT_BASE_DIR")/")
            fi
        fi

        # Add .git exclusion only for context mirrors (protection from Claude Code 1000 file limit)
        CONTEXT_EXCLUDES=("--exclude" ".git/")
        FINAL_EXCLUDES=("${RSYNC_EXCLUDES[@]}" "${DYNAMIC_EXCLUDES[@]}" "${CONTEXT_EXCLUDES[@]}")

        rsync -av --delete \
            "${FINAL_EXCLUDES[@]}" \
            "$project_root/" "$MIRROR_DIR/"
        echo "Context mirror created."
        echo

        # --- Step 3: Generate TREE.txt and Copy Context Files into the Mirror ---
        source "$ILMA_DIR/hooks/tree.sh"
        generate_tree_and_context "$project_root" "$project_name" "$MIRROR_DIR"

        echo
        echo "----------------------"
        echo " ✔ Success: Context mirror is ready at: $MIRROR_DIR"
        echo "----------------------"
    fi
}


# Handle archive creation (compressed backup)
create_archive() {
    local project_root="$1"
    local project_name
    project_name="$(basename "$project_root")"
    local archive_flag="$2"

    # Only create archive if requested
    if [[ "$CREATE_COMPRESSED_ARCHIVE" == "true" ]]; then
        echo
        echo "Creating compressed archive..."

        # Get archive extension based on compression type
        local archive_ext
        archive_ext=$(get_archive_extension "$COMPRESSION_TYPE")

        # Determine archive location
        local archive_dir archive_file
        if [[ -n "$archive_flag" ]]; then
            # If archive_flag ends with / or is a directory, treat it as target directory
            if [[ "$archive_flag" == */ ]] || [[ -d "$archive_flag" ]]; then
                archive_dir="$archive_flag"
                timestamp="$(date '+%Y%m%d-%H%M%S')"
                archive_file="$archive_dir/${project_name}-${timestamp}${archive_ext}"
            else
                archive_file="$archive_flag"
                archive_dir="$(dirname "$archive_file")"
            fi
        else
            # Use archive directory as configured (already resolved in config.sh)
            archive_dir="$(realpath "${ARCHIVE_BASE_DIR/#\~/$HOME}")"
            mkdir -p "$archive_dir"
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            archive_file="$archive_dir/${project_name}-${timestamp}${archive_ext}"
        fi

        # Convert RSYNC_EXCLUDES to tar exclude patterns
        tar_excludes=()
        for exclude in "${RSYNC_EXCLUDES[@]}"; do
            if [[ "$exclude" != "--exclude" ]]; then
                # Convert rsync patterns to tar patterns
                # rsync: '.git/' -> tar: './.git' (tar sees paths starting with ./)
                local tar_pattern="$exclude"
                if [[ "$tar_pattern" == *"/" ]]; then
                    # Remove trailing slash and prepend ./
                    tar_pattern="./${tar_pattern%/}"
                elif [[ "$tar_pattern" != ./* && "$tar_pattern" != "*"* ]]; then
                    # Prepend ./ for literal paths that don't start with ./ or contain *
                    tar_pattern="./$tar_pattern"
                fi
                tar_excludes+=(--exclude="$tar_pattern")
            fi
        done

        # Create archive directly in target location with verbosity
        local tar_option
        tar_option=$(get_tar_option "$COMPRESSION_TYPE")
        echo "  - Creating archive: $archive_file (compression: $COMPRESSION_TYPE)"
        if [[ -n "$tar_option" ]]; then
            tar $tar_option -cvf "$archive_file" -C "$project_root" "${tar_excludes[@]}" .
        else
            tar -cvf "$archive_file" -C "$project_root" "${tar_excludes[@]}" .
        fi

        if [[ $? -eq 0 ]]; then
            archive_size=$(du -sh "$archive_file" | cut -f1)
            echo "  - Archive created successfully: $archive_size"

            # Encrypt archive if GPG key configured
            if [[ -n "$GPG_KEY_ID" ]]; then
                local encrypted_file="${archive_file}${GPG_OUTPUT_EXTENSION}"
                echo "  - Encrypting archive with GPG..."
                if encrypt_existing_archive "$archive_file" "$encrypted_file" "$GPG_KEY_ID"; then
                    echo "  - Archive encrypted: $(basename "$encrypted_file")"
                    # Use encrypted file for remote sync
                    archive_file="$encrypted_file"
                else
                    echo "  - GPG encryption failed"
                fi
            fi

            # Sync to remote if configured
            if [[ -n "$REMOTE_SERVER" && -n "$REMOTE_PATH" ]]; then
                if sync_to_remote "$archive_file" "$REMOTE_SERVER" "$REMOTE_PATH" "$HASH_ALGORITHM" "$CLEANUP_AFTER_TRANSFER" "false"; then
                    echo "  - Remote sync completed successfully"
                else
                    echo "  - Remote sync failed"
                fi
            fi

            # Rotate old archives if MAX_ARCHIVES > 0
            if [[ "$MAX_ARCHIVES" -gt 0 && -z "$archive_flag" ]]; then
                # List archives by modification time, newest first
                # Use wildcard pattern that matches the current compression type
                local archive_pattern="$archive_dir/${project_name}-*${archive_ext}"
                mapfile -t archives < <(ls -1t $archive_pattern 2>/dev/null || true)

                if [[ ${#archives[@]} -gt $MAX_ARCHIVES ]]; then
                    echo "  - Rotating archives (keeping $MAX_ARCHIVES most recent)"
                    for ((i=MAX_ARCHIVES; i<${#archives[@]}; i++)); do
                        rm -f "${archives[i]}"
                        echo "    Removed: $(basename "${archives[i]}")"
                    done
                fi
            fi
        else
            echo "  - Warning: Failed to create compressed archive"
        fi
    fi
}

# If called directly as a command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle help flag
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat << 'EOF'
Usage: backup.sh [OPTIONS] [PROJECT_PATH]

Create backup and context mirror of a project (default ilma behavior).

OPTIONS:
  --backup [OUTPUT_PATH]               Create backup directory (explicit)
  --archive [OUTPUT_PATH]              Create compressed archive only
  --encrypt [OUTPUT_PATH]              Create encrypted archive only
  --context [OUTPUT_PATH]              Create context mirror only
  --remote SERVER:/PATH                Sync directly to remote server

ARGUMENTS:
  PROJECT_PATH    Path to project directory (default: current directory)

Examples:
  ./commands/backup.sh /path/to/project
  ./commands/backup.sh --archive /path/to/project
  ./commands/backup.sh --encrypt --remote srv:/backup

This tool uses the same configuration system as the main ilma command.
EOF
        exit 0
    fi

    # This would be the backup command entry point
    PROJECT_ROOT="${1:-$(pwd)}"
    ARCHIVE_FLAG="${2:-}"

    # Load configuration first
    source "$ILMA_DIR/commands/config.sh"
    load_config "$PROJECT_ROOT"
    handle_special_modes "$ARCHIVE_FLAG" "$PROJECT_ROOT"

    # Perform backup
    do_backup "$PROJECT_ROOT"

    # Create archive if needed
    create_archive "$PROJECT_ROOT" "$ARCHIVE_FLAG"
fi

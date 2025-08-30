#!/bin/bash
# lib/backup.sh - Main backup functionality for ilma

# Source required functions
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "$ILMA_DIR/lib/functions.sh"

# Main backup function
do_backup() {
    local project_root="$1"
    local project_name
    project_name="$(basename "$project_root")"
    
    # Configuration should be loaded before calling this function
    # Variables expected: BACKUP_BASE_DIR, CONFIG_FOUND, etc.
    
    # Configuration - resolve backup and context directories relative to project
    if [[ "${BACKUP_BASE_DIR}" == /* ]]; then
        # Absolute path
        resolved_backup_dir="${BACKUP_BASE_DIR/#\~/$HOME}"
    else
        # Relative path - resolve relative to project directory
        resolved_backup_dir="$project_root/$BACKUP_BASE_DIR"
    fi
    MAIN_BACKUP_DIR="$resolved_backup_dir/${project_name}.bak"
    
    # Set context mirror location
    if [[ -n "$CONTEXT_BASE_DIR" ]]; then
        if [[ "${CONTEXT_BASE_DIR}" == /* ]]; then
            # Absolute path
            resolved_context_dir="${CONTEXT_BASE_DIR/#\~/$HOME}"
        else
            # Relative path - resolve relative to project directory
            resolved_context_dir="$project_root/$CONTEXT_BASE_DIR"
        fi
        MIRROR_DIR="$resolved_context_dir/$project_name"
        MIRROR_DIR_BASENAME="$project_name"  # Still need this for exclusions
    else
        # Default: nested in backup directory
        MIRROR_DIR_BASENAME="$project_name"
        MIRROR_DIR="$MAIN_BACKUP_DIR/$MIRROR_DIR_BASENAME"
    fi
    
    # Skip backup and context steps in fallback mode
    if [[ "$CONFIG_FOUND" == "true" ]]; then
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
    fi
    
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
        
        FINAL_EXCLUDES=("${RSYNC_EXCLUDES[@]}" "${DYNAMIC_EXCLUDES[@]}")
        
        rsync -av --delete \
            "${FINAL_EXCLUDES[@]}" \
            "$project_root/" "$MIRROR_DIR/"
        echo "Context mirror created."
        echo
        
        # --- Step 3: Generate TREE.txt and Copy Context Files into the Mirror ---
        generate_tree_and_context "$project_root" "$project_name" "$MIRROR_DIR"
        
        echo
        echo "----------------------"
        echo " ✔ Success: Context mirror is ready at: $MIRROR_DIR"
        echo "----------------------"
    fi
}

# Generate TREE.txt and copy context files
generate_tree_and_context() {
    local project_root="$1"
    local project_name="$2" 
    local mirror_dir="$3"
    
    TREE_OUT="$mirror_dir/TREE.txt"
    echo "Step 3: Generating project tree and copying context files..."
    
    # Gather datestamp and latest commit info
    TREE_DATE="$(date -u +"%Y-%m-%d %H:%M UTC")"
    GIT_LOG=$(git -C "$project_root" log -1 --format='%cd|%h|%an|%s' --date=format:'%Y-%m-%d %H:%M' 2>/dev/null)
    if [[ -n "$GIT_LOG" ]]; then
      IFS='|' read -r commit_date commit_hash commit_author commit_msg <<< "$GIT_LOG"
      # Truncate commit message to 60 chars for clarity
      maxlen=60
      if (( ${#commit_msg} > maxlen )); then
        commit_msg="${commit_msg:0:maxlen}.."
      fi
      LATEST_COMMIT="Latest commit: $commit_date ($commit_hash) by $commit_author
        $commit_msg"
    else
      LATEST_COMMIT="Latest commit: N/A"
    fi
    
    cat > "$TREE_OUT" <<EOL
# TREE.txt snapshot for Context Mirror
# Date generated: $TREE_DATE
# $LATEST_COMMIT

~/build/
├── $project_name/
│   └── ... (The user's actual, complete project workspace)
│
└── ${project_name}.bak/
    ├── ... (A complete, 1:1 backup of the working directory)
    │
    └── $project_name/      <-- The nested, self-contained "Context Mirror" for LLM upload.
        ├── ... (The context project tree)
        │
        └── TREE.txt          Context file placed at the root of the mirror.
---
EOL
    
    tree -a -I "${TREE_EXCLUDES}|${project_name}.bak" "$project_root" | sed "s|$project_root|.|" >> "$TREE_OUT"
    echo "  - Project tree generated."
    
    # Copy context files if they exist
    for context_file in "${CONTEXT_FILES[@]}"; do
      if [[ -f "$project_root/$context_file" ]]; then
        cp "$project_root/$context_file" "$mirror_dir/"
        echo "  - Copied $(basename "$context_file")."
      fi
    done
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
        
        # Determine archive location
        local archive_dir archive_file
        if [[ -n "$archive_flag" ]]; then
            # If archive_flag ends with / or is a directory, treat it as target directory
            if [[ "$archive_flag" == */ ]] || [[ -d "$archive_flag" ]]; then
                archive_dir="$archive_flag"
                timestamp="$(date '+%Y%m%d-%H%M%S')"
                archive_file="$archive_dir/${project_name}-${timestamp}.tar.zst"
            else
                archive_file="$archive_flag"
                archive_dir="$(dirname "$archive_file")"
            fi
        else
            # Resolve archive directory relative to project directory, not current directory
            if [[ "${ARCHIVE_BASE_DIR}" == /* ]]; then
                # Absolute path
                archive_dir="$(realpath "${ARCHIVE_BASE_DIR/#\~/$HOME}")"
            else
                # Relative path - resolve relative to project directory
                archive_dir="$(realpath "$project_root/${ARCHIVE_BASE_DIR}")"
            fi
            mkdir -p "$archive_dir"
            timestamp="$(date '+%Y%m%d-%H%M%S')"
            archive_file="$archive_dir/${project_name}-${timestamp}.tar.zst"
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
        echo "  - Creating archive: $archive_file"
        if tar --zstd -cvf "$archive_file" -C "$project_root" "${tar_excludes[@]}" .; then
            archive_size=$(du -sh "$archive_file" | cut -f1)
            echo "  - Archive created successfully: $archive_size"
            
            # Rotate old archives if MAX_ARCHIVES > 0
            if [[ "$MAX_ARCHIVES" -gt 0 && -z "$archive_flag" ]]; then
                # List archives by modification time, newest first
                mapfile -t archives < <(ls -1t "$archive_dir"/"${project_name}"-*.tar.zst 2>/dev/null || true)
                
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
    # This would be the backup command entry point
    PROJECT_ROOT="${1:-$(pwd)}"
    ARCHIVE_FLAG="${2:-}"
    
    # Load configuration first
    source "$ILMA_DIR/lib/config.sh"
    load_config "$PROJECT_ROOT"
    handle_special_modes "$ARCHIVE_FLAG" "$PROJECT_ROOT"
    
    # Perform backup
    do_backup "$PROJECT_ROOT"
    
    # Create archive if needed
    create_archive "$PROJECT_ROOT" "$ARCHIVE_FLAG"
fi

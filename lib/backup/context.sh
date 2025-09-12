#!/bin/bash
# lib/backup/context.sh - Context-only operations

# Source shared utility functions
source "$ILMA_DIR/lib/functions.sh"

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

# Create context mirror only (no full backup)
create_context_only() {
    local project_root="$1"
    local output_path="$2"
    local project_name
    project_name="$(basename "$project_root")"

    if [[ -z "$output_path" ]]; then
        # Use unified path resolution with CONTEXT_BASE_DIR
        output_path=$(resolve_base_dir "$CONTEXT_BASE_DIR" "$project_root" "$project_name" ".context")
    fi

    echo "Creating context mirror: $output_path"

    # Create context directory
    mkdir -p "$output_path"

    # Build rsync command for context files only
    local rsync_args=(
        "--archive"
        "--delete"
        "--human-readable"
    )

    # Add context file patterns as includes (if any)
    if [[ ${#CONTEXT_FILES[@]} -gt 0 ]]; then
        for pattern in "${CONTEXT_FILES[@]}"; do
            rsync_args+=("--include=$pattern")
        done
    fi

    # Use project-type exclusion patterns (inverse logic: exclude build artifacts, include source)
    if [[ ${#RSYNC_EXCLUDES[@]} -gt 0 ]]; then
        # Always exclude .git directory in context mirrors (version control metadata not needed for LLMs)
        rsync_args+=("--exclude=.git/")
        for exclude_arg in "${RSYNC_EXCLUDES[@]}"; do
            if [[ "$exclude_arg" != "--exclude" ]]; then
                rsync_args+=("--exclude=$exclude_arg")
            fi
        done
    else
        echo "No project type specified, loading combined exclusions from all project configs"
        # Always exclude .git directory in context mirrors (version control metadata not needed for LLMs)
        rsync_args+=("--exclude=.git/")
        # Load and combine exclusions from all project config files
        for config_file in "$ILMA_DIR"/configs/*-project.ilma.conf; do
            if [[ -f "$config_file" ]]; then
                # Source the config in a subshell to extract RSYNC_EXCLUDES
                local temp_excludes=()
                while IFS= read -r line; do
                    if [[ "$line" =~ ^[[:space:]]*--exclude ]]; then
                        temp_excludes+=("$line")
                    fi
                done < <(grep -E "^\s*--exclude" "$config_file" || true)

                # Add to rsync args
                for exclude_arg in "${temp_excludes[@]}"; do
                    exclude_pattern=$(echo "$exclude_arg" | sed "s/^[[:space:]]*--exclude[[:space:]]*['\"]*//" | sed "s/['\"][[:space:]]*$//" | sed "s/^[[:space:]]*//" | sed "s/[[:space:]]*$//")
                    [[ -n "$exclude_pattern" ]] && rsync_args+=("--exclude=$exclude_pattern")
                done
            fi
        done
    fi

    # Add source and destination
    rsync_args+=("$project_root/")
    rsync_args+=("$output_path/")

    if rsync "${rsync_args[@]}"; then
        echo "Context mirror created: $output_path"

        # Generate file listing
        if command -v tree >/dev/null 2>&1; then
            tree "$output_path" > "$output_path/TREE.txt"
        else
            find "$output_path" -type f | sort > "$output_path/FILES.txt"
        fi

        return 0
    else
        echo "Error: Failed to create context mirror" >&2
        return 1
    fi
}
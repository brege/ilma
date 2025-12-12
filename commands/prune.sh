#!/bin/bash
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_template.sh"
template_initialize_paths

source "$ILMA_DIR/commands/config.sh"
source "$ILMA_DIR/lib/deps/compression.sh"
source "$ILMA_DIR/commands/console.sh"
source "$ILMA_DIR/lib/log.sh"

# Find files by pattern (overrides config-based scanning)
find_by_pattern() {
    local project_root="$1"
    local pattern="$2"
    local files=()

    # Handle directory patterns (like "Trash")
    if [[ "$pattern" =~ ^[^*?]+$ ]] && [[ -d "$project_root/$pattern" ]]; then
        # Pattern is a directory name - include the entire directory
        files+=("$project_root/$pattern")
    else
        # Pattern contains wildcards - find matching files and directories
        while IFS= read -r -d '' item; do
            files+=("$item")
        done < <(find "$project_root" -name "$pattern" -print0 2>/dev/null)
    fi

    printf '%s\n' "${files[@]}"
}

usage() {
    cat <<EOF
Usage: ilma prune [OPTIONS] [PROJECT_PATH]

Analyze and optionally remove junk files from projects based on project type configuration.

OPTIONS:
  --type TYPE      Project type configuration to use
                   Available types: bash, latex, node, python, all
                   Multiple types: --type node --type python OR --type 'node|python'
  --pattern PATTERN Override config with custom pattern (e.g. "*.json", "Trash")
  --verbose        Show detailed analysis with file paths
  --bak            Create complete backup before deleting files
  --delete         Delete junk files without creating backup (DANGEROUS)
  -h, --help       Show this help message

MODES:
  Default          Dry-run analysis only - shows summary of junk files found
  --verbose        Detailed dry-run with full file listing
  --bak            Creates complete compressed backup then deletes junk files
  --delete         Deletes junk files immediately (no backup created)

EXAMPLES:
  ilma prune                           # Dry-run analysis of current directory
  ilma prune --verbose                 # Detailed analysis with file paths
  ilma prune --type python --verbose   # Analyze Python project with details
  ilma prune --pattern "*.json"        # Find all JSON files for removal
  ilma prune --pattern "Trash" --verbose # Show contents of Trash directory
  ilma prune --pattern "*.json" --delete # Delete all JSON files
  ilma prune --type latex --bak        # Backup LaTeX project then clean
  ilma prune --delete                  # Delete junk files (no backup)

SAFETY:
  - Default mode is always dry-run (no files deleted)
  - --bak creates complete project backup before deletion
  - --delete mode bypasses backup creation
  - Use --verbose to preview what will be deleted before using --bak or --delete

EOF
    exit 0
}

type_name=""
pattern_override=""
verbose_option=false
backup_option=false
delete_option=false
project_path=""

parse_prune_arguments() {
    type_name=""
    pattern_override=""
    verbose_option=false
    backup_option=false
    delete_option=false
    project_path=""

    while (( $# > 0 )); do
        case "$1" in
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
            --pattern)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --pattern requires an argument" >&2
                    exit 1
                fi
                pattern_override="$2"
                shift 2
                ;;
            --verbose)
                verbose_option=true
                shift
                ;;
            --bak)
                backup_option=true
                shift
                ;;
            --delete)
                delete_option=true
                shift
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

do_prune() {
    local project_root="$1"
    local verbose="${2:-false}"
    local type="${3:-${TYPE-}}"
    local delete_mode="${4:-false}"
    local pattern="${5:-}"
    local project_name
    project_name="$(basename "$project_root")"

    echo "Prune analysis for: $project_name"
    echo "Directory: $project_root"
    if [[ -n "$pattern" ]]; then
        echo "Pattern: $pattern (overrides config)"
    else
        echo "Type: $type"
    fi
    echo

    if [[ "$delete_mode" == "true" ]]; then
        # Delete mode: just do it, no previews or warnings
        # Disable strict error handling for deletion loop
        set +e

        # Get files to delete - use pattern if specified, otherwise use scan.sh
        if [[ -n "$pattern" ]]; then
            mapfile -t files < <(find_by_pattern "$project_root" "$pattern")
        else
            scan_args=()
            [[ -n "$type" ]] && scan_args+=(--type "$type")
            scan_args+=("$project_root")
            mapfile -t files < <("$ILMA_DIR/commands/scan.sh" "${scan_args[@]}")
        fi

        if (( ${#files[@]} == 0 )); then
            echo "No junk files found - project appears clean!"
            return 0
        fi

        # Initialize logging for destructive operation
        source "$ILMA_DIR/lib/log.sh"
        local log_file
        log_file="$(get_log_file "prune")"
        init_log "$log_file" "prune" "$project_root"
        log_summary "$log_file" "Starting prune operation on ${#files[@]} files"

        echo "Logging operation to: $log_file"

        local deleted=0
        local failed=0
        for file in "${files[@]}"; do
            if rm -rf "$file" 2>/dev/null; then
                echo "DELETED: $file"
                log_file_op "$log_file" "DELETE" "$file" "SUCCESS"
                ((deleted++))
            else
                echo "FAILED: $file"
                log_file_op "$log_file" "DELETE" "$file" "FAILED"
                ((failed++))
            fi
        done

        log_summary "$log_file" "Prune operation completed: $deleted deleted, $failed failed"
        echo "Operation logged to: $log_file"
        set -e
    elif [[ "$verbose" == "true" ]]; then
        # Verbose dry-run: show detailed analysis with individual paths
        echo "Verbose analysis - showing all prunable paths:"
        echo

        if [[ -n "$pattern" ]]; then
            # Use pattern matching
            mapfile -t files < <(find_by_pattern "$project_root" "$pattern")
            if (( ${#files[@]} == 0 )); then
                echo "No files matching pattern '$pattern' found."
            else
                printf '%s\n' "${files[@]}"
                echo
                echo "Summary: Found ${#files[@]} items matching pattern '$pattern'"
            fi
        else
            # Use scan.sh
            scan_args=()
            [[ -n "$type" ]] && scan_args+=(--type "$type")
            scan_args+=("$project_root")
            "$ILMA_DIR/commands/scan.sh" "${scan_args[@]}"
            echo
            echo "Summary:"
            scan_args_stats=()
            [[ -n "$type" ]] && scan_args_stats+=(--type "$type")
            scan_args_stats+=(--stats=excludes "$project_root")
            "$ILMA_DIR/commands/scan.sh" "${scan_args_stats[@]}"
        fi
    else
        # Default dry-run: show summary and preview
        if [[ -n "$pattern" ]]; then
            # Use pattern matching
            mapfile -t files < <(find_by_pattern "$project_root" "$pattern")
            if (( ${#files[@]} == 0 )); then
                echo "No items matching pattern '$pattern' found - directory is clean!"
                return 0
            fi

            echo "Found ${#files[@]} items matching pattern '$pattern'"
        else
            # Use scan.sh
            scan_args=()
            [[ -n "$type" ]] && scan_args+=(--type "$type")
            scan_args+=("$project_root")
            mapfile -t files < <("$ILMA_DIR/commands/scan.sh" "${scan_args[@]}")
            if (( ${#files[@]} == 0 )); then
                echo "No junk files found - project appears clean!"
                return 0
            fi

            echo "Found ${#files[@]} junk items"
        fi

        echo
        echo "Preview (first 5 items):"
        for ((i=0; i<5 && i<${#files[@]}; i++)); do
            echo "  $(basename "${files[i]}")"
        done
        if (( ${#files[@]} > 5 )); then
            echo "  ... and $((${#files[@]} - 5)) more items"
        fi
        echo
        echo "Use --verbose to see detailed analysis"
        echo "Use --delete to remove these files"
    fi
}

prune_main() {
    parse_prune_arguments "$@"

    local project_root
    project_root="$(template_require_project_root "$project_path")"
    load_config "$project_root" "$type_name"

    if [[ "$backup_option" == "true" ]]; then
        handle_special_modes "" "$project_root"
    fi

    local delete_mode="false"
    if [[ "$backup_option" == "true" || "$delete_option" == "true" ]]; then
        delete_mode="true"
    fi

    local project_name
    project_name="$(basename "$project_root")"

    if [[ "$backup_option" == "true" ]]; then
        echo "Creating complete backup before deletion..."
        local parent_directory
        parent_directory="$(dirname "$project_root")"
        local archive_extension
        archive_extension="$(get_archive_extension "$COMPRESSION_TYPE")"
        local backup_archive
        backup_archive="$parent_directory/${project_name}.orig${archive_extension}"

        local tar_option
        tar_option="$(get_tar_option "$COMPRESSION_TYPE")"
        local tar_command
        if [[ -n "$tar_option" ]]; then
            tar_command=("tar" "$tar_option" "-cf")
        else
            tar_command=("tar" "-cf")
        fi

        if "${tar_command[@]}" "$backup_archive" -C "$project_root" .; then
            echo "Complete backup created: $backup_archive"
        else
            echo "ERROR: Failed to create backup archive" >&2
            exit 1
        fi
        echo
        echo "Backup complete. Now proceeding with junk file deletion..."
        echo
    fi

    local verbose_flag="false"
    if [[ "$verbose_option" == "true" ]]; then
        verbose_flag="true"
    fi

    do_prune "$project_root" "$verbose_flag" "$type_name" "$delete_mode" "$pattern_override"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    template_dispatch usage prune_main "$@"
fi

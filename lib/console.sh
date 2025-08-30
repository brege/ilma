#!/bin/bash
# lib/console.sh - Console summary and analysis functionality for ilma

# Source required functions
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "$ILMA_DIR/lib/functions.sh"

usage() {
    cat <<EOF
Usage: ilma console [PROJECT_PATH]

Display project statistics and mirror reduction analysis.

ARGUMENTS:
  PROJECT_PATH     Path to project directory (default: current directory)

OPTIONS:
  -h, --help       Show this help message

DESCRIPTION:
  Shows detailed statistics about your project including:
  - File counts by type (.py, .md, .json, etc.)
  - Line counts and size analysis
  - Mirror reduction metrics (if backup exists)
  - Git repository information (commits, latest commit)
  - Token estimation for LLM context planning

  The console view helps evaluate the impact of including your project
  in an LLM's context window by showing size and complexity metrics.

EXAMPLES:
  ilma console                    # Show stats for current directory
  ilma console ~/my-project       # Show stats for specific project

NOTES:
  - Statistics reflect actual files, not git-tracked files
  - Mirror reduction shows comparison with existing ilma backup
  - Token estimation assumes ~4 characters per token
  - Git info shown only if project is a git repository

EOF
    exit 0
}

# Show console summary (stats only, no backup)
show_console_summary() {
    local project_root="$1"
    local project_name
    project_name="$(basename "$project_root")"

    SOURCE_DIR="$project_root"

    # Check if we have an existing mirror to compare against
    MIRROR_DIR=""
    HAS_MIRROR=false

    if [[ "$CONFIG_FOUND" == "true" ]]; then
        # Set mirror directory path (same logic as backup.sh)
        if [[ -n "$CONTEXT_BASE_DIR" ]]; then
            MIRROR_DIR="$CONTEXT_BASE_DIR/$project_name"
        else
            MAIN_BACKUP_DIR="$BACKUP_BASE_DIR/${project_name}.bak"
            MIRROR_DIR="$MAIN_BACKUP_DIR/$project_name"
        fi

        # Check if mirror actually exists
        if [[ -d "$MIRROR_DIR" ]]; then
            HAS_MIRROR=true
        fi
    fi

    # --- Mirror Reduction Stats Summary ---

    declare -A files_source files_mirror lines_source lines_mirror

    # Count files and lines using find (not git) for consistency with backup behavior
    count_files_by_pattern() {
        local dir="$1"
        local pattern="$2"
        find "$dir" -type f -name "$pattern" 2>/dev/null | wc -l
    }

    count_lines_by_pattern() {
        local dir="$1"
        local pattern="$2"
        local files=()
        mapfile -t files < <(find "$dir" -type f -name "$pattern" 2>/dev/null)
        if [[ ${#files[@]} -gt 0 ]]; then
            wc -l "${files[@]}" 2>/dev/null | tail -n1 | awk '{print $1}'
        else
            echo 0
        fi
    }

    for ext in "${EXTENSIONS[@]}"; do
      files_source[$ext]=$(count_files_by_pattern "$SOURCE_DIR" "*.${ext}")
      lines_source[$ext]=$(count_lines_by_pattern "$SOURCE_DIR" "*.${ext}")
      files_source[$ext]=${files_source[$ext]:-0}
      lines_source[$ext]=${lines_source[$ext]:-0}

      if [[ "$HAS_MIRROR" == "true" ]]; then
          files_mirror[$ext]=$(count_files_by_pattern "$MIRROR_DIR" "*.${ext}")
          lines_mirror[$ext]=$(count_lines_by_pattern "$MIRROR_DIR" "*.${ext}")
          files_mirror[$ext]=${files_mirror[$ext]:-0}
          lines_mirror[$ext]=${lines_mirror[$ext]:-0}
      else
          files_mirror[$ext]=0
          lines_mirror[$ext]=0
      fi
    done

    total_files() {
      find "$1" -type f 2>/dev/null | wc -l
    }
    total_lines() {
      local files=()
      mapfile -t files < <(find "$1" -type f 2>/dev/null)
      if [[ ${#files[@]} -gt 0 ]]; then
        wc -l "${files[@]}" 2>/dev/null | tail -n1 | awk '{print $1}'
      else
        echo 0
      fi
    }
    total_size() {
      du -sm "$1" | awk '{print $1}'
    }

    total_files_source=$(total_files "$SOURCE_DIR")
    size_source=$(total_size "$SOURCE_DIR")
    total_lines_source=$(total_lines "$SOURCE_DIR")

    if [[ "$HAS_MIRROR" == "true" ]]; then
        total_files_mirror=$(total_files "$MIRROR_DIR")
        total_lines_mirror=$(total_lines "$MIRROR_DIR")
        size_mirror=$(total_size "$MIRROR_DIR")
        delta_files=$((total_files_source - total_files_mirror))
        delta_lines=$((total_lines_source - total_lines_mirror))
        delta_size=$((size_source - size_mirror))
    else
        total_files_mirror=0
        total_lines_mirror=0
        size_mirror=0
        delta_files=0
        delta_lines=0
        delta_size=0
    fi

    percent() {
      local orig="$1"
      local new="$2"
      local pct
      if [[ "$orig" -eq 0 ]]; then
        pct="N/A"
      else
        pct=$(awk "BEGIN {printf \"%.1f%%\", ($orig-$new)*100/$orig}")
      fi

      local pad="        "
      local padded="${pad}${pct}"
      padded="${padded: -8}"

      local color_reset="\033[0m"
      local color=""
      if [[ "$pct" =~ ^[0-9]+(\.[0-9]+)?%$ ]]; then
        local val="${pct%\%}"
        if (( $(echo "$val > 50" | bc -l) )); then
          color="\033[1;32m"
        elif (( $(echo "$val > 25" | bc -l) )); then
          color="\033[1;33m"
        fi
        printf "%b%s%b" "$color" "$padded" "$color_reset"
      else
        printf "%s" "$padded"
      fi
    }

    echo
    if [[ "$HAS_MIRROR" == "true" ]]; then
        echo "Mirror Reduction Stats"
        echo "----------------------"
        printf "%-18s %10s %10s %10s %8b\n" "Metric" "Source" "Mirror" "Delta" "Reduction"
        printf "%-18s %10s %10s %10s %8s\n" "-----"  "------" "------" "-----" "--------"
    else
        echo "Project Statistics"
        echo "------------------"
        printf "%-18s %10s\n" "Metric" "Count"
        printf "%-18s %10s\n" "-----"  "-----"
    fi

    if [[ "$HAS_MIRROR" == "true" ]]; then
        printf "%-18s %10s %10s %10s %8b\n" "Total files" "$total_files_source" "$total_files_mirror" "$delta_files" "$(percent "$total_files_source" "$total_files_mirror")"
        for ext in "${EXTENSIONS[@]}"; do
          delta=$((files_source[$ext] - files_mirror[$ext]))
          printf "%-18s %10s %10s %10s %8b\n" ".${ext} files" "${files_source[$ext]}" "${files_mirror[$ext]}" "$delta" "$(percent "${files_source[$ext]}" "${files_mirror[$ext]}")"
        done

        printf "%-18s %10s %10s %10s %8b\n" "Total lines" "$total_lines_source" "$total_lines_mirror" "$delta_lines" "$(percent "$total_lines_source" "$total_lines_mirror")"
        for ext in "${EXTENSIONS[@]}"; do
          delta=$((lines_source[$ext] - lines_mirror[$ext]))
          printf "%-18s %10s %10s %10s %8b\n" ".${ext} lines" "${lines_source[$ext]}" "${lines_mirror[$ext]}" "$delta" "$(percent "${lines_source[$ext]}" "${lines_mirror[$ext]}")"
        done

        printf "%-18s %10s %10s %10s %8b\n" "Total size (MB)" "$size_source" "$size_mirror" "$delta_size" "$(percent "$size_source" "$size_mirror")"
    else
        printf "%-18s %10s\n" "Total files" "$total_files_source"
        for ext in "${EXTENSIONS[@]}"; do
          if [[ "${files_source[$ext]}" -gt 0 ]]; then
            printf "%-18s %10s\n" ".${ext} files" "${files_source[$ext]}"
          fi
        done

        printf "%-18s %10s\n" "Total lines" "$total_lines_source"
        for ext in "${EXTENSIONS[@]}"; do
          if [[ "${lines_source[$ext]}" -gt 0 ]]; then
            printf "%-18s %10s\n" ".${ext} lines" "${lines_source[$ext]}"
          fi
        done

        printf "%-18s %10s\n" "Total size (MB)" "$size_source"
    fi

    if [[ "$HAS_MIRROR" == "true" ]]; then
        echo "----------------------"
    else
        echo "------------------"
    fi

    if [[ "$HAS_MIRROR" == "true" ]]; then
        mirror_chars=$(find "$MIRROR_DIR" -type f -exec cat {} + | wc -c)
        token_estimate=$((mirror_chars / 4))
        printf "Mirror token estimate: %s (~4 chars per token)\n" "$token_estimate"
    else
        source_chars=$(find "$SOURCE_DIR" -type f -exec cat {} + 2>/dev/null | wc -c)
        token_estimate=$((source_chars / 4))
        printf "Source token estimate: %s (~4 chars per token)\n" "$token_estimate"
    fi

    commit_count=$(git -C "$SOURCE_DIR" rev-list --count HEAD 2>/dev/null || echo "N/A")
    git_log=$(git -C "$SOURCE_DIR" log -1 --format='%cd|%h|%s' --date=format:'%Y-%m-%d:%H:%M' 2>/dev/null)
    if [[ -n "$git_log" ]]; then
      IFS='|' read -r commit_date commit_hash commit_msg <<< "$git_log"
      # Truncate commit message to 42 chars for proper alignment
      maxlen=42
      if (( ${#commit_msg} > maxlen )); then
        commit_msg="${commit_msg:0:maxlen}.."
      fi
      latest_commit="$commit_date ($commit_hash) $commit_msg"
    else
      latest_commit="N/A"
    fi

    printf "git: [ commits: %s ][ latest: %s ]\n" "$commit_count" "$latest_commit"
    echo "tip: ilma console (this display) | ilma --help"
}

# Show backup/mirror stats after backup completion
show_backup_stats() {
    local project_root="$1"
    local mirror_dir="$2"
    local project_name
    project_name="$(basename "$project_root")"

    # Only show stats in configured mode
    if [[ "$CONFIG_FOUND" == "true" ]]; then
        SOURCE_DIR="$project_root"
        MIRROR_DIR="$mirror_dir"

        # Use the same stats logic as console summary
        show_console_summary "$project_root"
    fi
}

# If called directly as a command
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # This would be the analyze/console command entry point
    PROJECT_ROOT="${1:-$(pwd)}"

    # Load configuration first
    source "$ILMA_DIR/lib/config.sh"
    load_config "$PROJECT_ROOT"

    # Show console summary
    show_console_summary "$PROJECT_ROOT"
fi

#!/bin/bash

# Extracted functions for ilma script usage

# --- counts number of total lines for each file extension ---
# (uses .gitignore if in git repo)
# (does NOT ignore anything if not in git repo)
git-count-lines() {
  local dir="$1"
  shift

  if [[ -z "$dir" ]]; then
    echo "Usage: git-counts-lines <directory> [pattern1] [pattern2] ..."
    echo "Example: git-counts-lines ./repo '*.js' '*.md'"
    return 1
  fi

  count_lines() {
    # Filter out files that don't exist before passing to wc
    local existing_files=()
    for file in "$@"; do
      [[ -f "$file" ]] && existing_files+=("$file")
    done

    if [[ ${#existing_files[@]} -gt 0 ]]; then
      awk '{s+=$1} END {print s}' <<<"$(xargs -d '\n' wc -l < <(printf '%s\n' "${existing_files[@]}"))"
    else
      echo 0
    fi
  }

  # Check for git repo and .gitignore
  if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null && [[ -f "$dir/.gitignore" ]]; then
    # Use git ls-files (respects .gitignore)
    if [[ $# -eq 0 ]]; then
      git -C "$dir" ls-files | awk -F. 'NF>1{print $NF}' | sort | uniq | while read -r ext; do
        mapfile -t files < <(git -C "$dir" ls-files "*.$ext")
        [ ${#files[@]} -eq 0 ] && continue
        num_files=${#files[@]}
        num_lines=$(count_lines "${files[@]}")
        printf ".%-8s %4d files %7d lines\n" "$ext" "$num_files" "$num_lines"
      done
    else
      for pattern in "$@"; do
        pattern="${pattern//\'/}"
        mapfile -t files < <(git -C "$dir" ls-files "$pattern")
        num_files=${#files[@]}
        if ((num_files == 0)); then
          printf "%-10s %4d files %7d lines\n" "$pattern:" 0 0
        else
          num_lines=$(count_lines "${files[@]}")
          printf "%-10s %4d files %7d lines\n" "$pattern:" "$num_files" "$num_lines"
        fi
      done
    fi
  else
    # Not a git repo, or no .gitignore: use find (does NOT ignore anything)
    if [[ $# -eq 0 ]]; then
      find "$dir" -type f | awk -F. 'NF>1{print $NF}' | sort | uniq | while read -r ext; do
        mapfile -t files < <(find "$dir" -type f -name "*.$ext")
        [ ${#files[@]} -eq 0 ] && continue
        num_files=${#files[@]}
        num_lines=$(count_lines "${files[@]}")
        printf ".%-8s %4d files %7d lines\n" "$ext" "$num_files" "$num_lines"
      done
    else
      for pattern in "$@"; do
        pattern="${pattern//\'/}"
        mapfile -t files < <(find "$dir" -type f -name "$pattern")
        num_files=${#files[@]}
        if ((num_files == 0)); then
          printf "%-10s %4d files %7d lines\n" "$pattern:" 0 0
        else
          num_lines=$(count_lines "${files[@]}")
          printf "%-10s %4d files %7d lines\n" "$pattern:" "$num_files" "$num_lines"
        fi
      done
    fi
  fi
}

# --- Counts number of files for each file extension ---
# (uses .gitignore if in git repo)
# (does NOT ignore anything if not in git repo)
git-count-files() {
  local dir="$1"
  shift

  if [[ -z "$dir" ]]; then
    echo "Usage: git-count-files <directory> [pattern1] [pattern2] ..."
    echo "Example: git-count-files ./repo '*.js' '*.md'"
    return 1
  fi

  count_by_extension() {
    awk -F. 'NF>1{print $NF}' | sort | uniq -c | sort -nr | awk '{printf ".%-8s %s\n", $2, $1}'
  }

  # Check if it's a git repo with tracked files
  if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
    local gitfiles
    gitfiles=$(git -C "$dir" ls-files)
    if [[ -n "$gitfiles" ]]; then
      if [[ $# -eq 0 ]]; then
        printf "%s\n" "$gitfiles" | count_by_extension
      else
        for pattern in "$@"; do
          pattern="${pattern//\'/}"
          count=$(git -C "$dir" ls-files "$pattern" | wc -l)
          printf "%-10s %s\n" "$pattern:" "$count"
        done
      fi
      return 0
    fi
    # If no tracked files, fall through to find
  fi

  # Not a git repo or no tracked files: use find
  if [[ $# -eq 0 ]]; then
    find "$dir" -type f | count_by_extension
  else
    for pattern in "$@"; do
      pattern="${pattern//\'/}"
      count=$(find "$dir" -type f -name "$pattern" | wc -l)
      printf "%-10s %s\n" "$pattern:" "$count"
    done
  fi
}

# Cached rsync capability detection
declare -g _ILMA_RSYNC_CAPS_CHECKED=0
declare -Ag _ILMA_RSYNC_CAPABILITIES=()

ilma_detect_rsync_capabilities() {
    if (( _ILMA_RSYNC_CAPS_CHECKED )); then
        return
    fi

    _ILMA_RSYNC_CAPS_CHECKED=1
    local version_output
    version_output=$(rsync --version 2>/dev/null || true)

    if [[ -z "$version_output" ]]; then
        return
    fi

    if grep -qiE '(^|\s)acl(s)?(\s|$)' <<<"$version_output"; then
        _ILMA_RSYNC_CAPABILITIES[acl]=1
    fi
    if grep -qiE '(^|\s)xattr(s)?(\s|$)' <<<"$version_output"; then
        _ILMA_RSYNC_CAPABILITIES[xattr]=1
    fi
}

ilma_rsync_supports_capability() {
    local capability="$1"
    ilma_detect_rsync_capabilities
    [[ "${_ILMA_RSYNC_CAPABILITIES[$capability]:-0}" -eq 1 ]]
}

ilma_append_rsync_preserve_args() {
    local -n _dest=$1
    ilma_detect_rsync_capabilities
    _dest+=(--archive --human-readable)
    if ilma_rsync_supports_capability "acl"; then
        _dest+=(--acls)
    fi
    if ilma_rsync_supports_capability "xattr"; then
        _dest+=(--xattrs)
    fi
}

# Execute command with progress bar if pv is available and file is large enough
execute_with_progress() {
    local estimated_size="$1"
    local success_msg="$2"
    local error_msg="$3"
    shift 3
    local command_args=("$@")

    if command -v pv >/dev/null 2>&1 && [[ -n "$estimated_size" ]] && [[ "$estimated_size" -gt 1048576 ]]; then
        # Use pv for files larger than 1MB - assumes command outputs to stdout
        if "${command_args[@]}" | pv -s "$estimated_size" -p -t -e -r -b >/dev/null; then
            echo "$success_msg"
            return 0
        else
            echo "$error_msg" >&2
            return 1
        fi
    else
        # Fallback to regular command execution
        if "${command_args[@]}"; then
            echo "$success_msg"
            return 0
        else
            echo "$error_msg" >&2
            return 1
        fi
    fi
}

# Execute pipeline with progress bar if pv is available and file is large enough
execute_pipeline_with_progress() {
    local estimated_size="$1"
    local success_msg="$2"
    local error_msg="$3"
    local first_cmd="$4"
    local second_cmd="$5"

    if command -v pv >/dev/null 2>&1 && [[ -n "$estimated_size" ]] && [[ "$estimated_size" -gt 1048576 ]]; then
        # Use pv for files larger than 1MB
        if eval "$first_cmd" | pv -s "$estimated_size" -p -t -e -r -b | eval "$second_cmd"; then
            echo "$success_msg"
            return 0
        else
            echo "$error_msg" >&2
            return 1
        fi
    else
        # Fallback to regular pipeline execution
        if eval "$first_cmd" | eval "$second_cmd"; then
            echo "$success_msg"
            return 0
        else
            echo "$error_msg" >&2
            return 1
        fi
    fi
}

# Calculate and format compression ratio message
format_compression_message() {
    local base_msg="$1"
    local output_path="$2"
    local estimated_size="$3"

    if [[ -f "$output_path" && -n "$estimated_size" ]]; then
        local final_size
        final_size=$(stat -c%s "$output_path" 2>/dev/null)
        if [[ -n "$final_size" && "$final_size" -gt 0 && "$estimated_size" -gt 0 ]]; then
            local compression_ratio
            compression_ratio=$((100 - (final_size * 100 / estimated_size)))
            echo "$base_msg (compressed by ${compression_ratio}%)"
        else
            echo "$base_msg"
        fi
    else
        echo "$base_msg"
    fi
}

# Smart copy function that detects filesystem capabilities and uses optimal method
smart_copy() {
    local source="$1"
    local dest="$2"
    shift 2
    local rsync_args=("$@")

    # Check for rsync-specific arguments that cp can't handle
    local has_rsync_specific=false
    for arg in "${rsync_args[@]}"; do
        if [[ "$arg" =~ ^--(include|exclude|delete|archive|human-readable|itemize-changes) ]]; then
            has_rsync_specific=true
            break
        elif [[ "$arg" =~ ^--(info|partial|acls|xattrs) ]]; then
            has_rsync_specific=true
            break
        elif [[ "$arg" == -* && "$arg" != --* ]]; then
            if [[ "$arg" == *a* || "$arg" == *A* || "$arg" == *X* || "$arg" == *h* ]]; then
                has_rsync_specific=true
                break
            fi
        fi
    done

    # Check if this is a local-to-local copy (both paths exist locally)
    if [[ -d "$source" || -f "$source" ]] && [[ "$dest" != *:* ]] && [[ "$has_rsync_specific" == "false" ]]; then
        # Local copy - check filesystem types
        local source_fs dest_fs
        source_fs=$(stat -f -c %T "$source" 2>/dev/null)
        dest_fs=$(stat -f -c %T "$(dirname "$dest")" 2>/dev/null)

        # If both are on same filesystem and filesystem supports optimization, use cp
        if [[ "$source_fs" == "$dest_fs" ]] && [[ "$source_fs" =~ ^(btrfs|xfs|ext4|tmpfs)$ ]]; then
            echo "Using optimized local copy (${source_fs})"

            # Clean slate approach: rm + cp --reflink
            # Safety: never remove a symlink path
            if [[ -d "$dest" && ! -L "$dest" ]]; then
                rm -rf "$dest"
            fi

            # Create parent directory if needed
            mkdir -p "$(dirname "$dest")"

            # If source contains sockets, avoid cp and fall back to rsync
            if find "$source" -type s -print -quit 2>/dev/null | grep -q .; then
                echo "Sockets detected in source; using rsync without specials/devices"
                smart_copy_rsync "$source" "$dest" "${rsync_args[@]}" --no-specials --no-devices
            else
                # Use cp with reflink for maximum performance
                if cp -r --reflink=auto "$source" "$dest" 2>/dev/null; then
                    return 0
                else
                    echo "Reflink copy failed, falling back to rsync"
                    smart_copy_rsync "$source" "$dest" "${rsync_args[@]}"
                fi
            fi
        else
            # Different filesystems or unsupported - use rsync
            smart_copy_rsync "$source" "$dest" "${rsync_args[@]}"
        fi
    else
        # Remote copy or complex rsync args - always use rsync
        smart_copy_rsync "$source" "$dest" "${rsync_args[@]}"
    fi
}

# Rsync wrapper used as fallback or for remote operations
smart_copy_rsync() {
    local source="$1"
    local dest="$2"
    shift 2
    local rsync_args=("$@")

    echo "Using rsync"
    # Default to skipping devices/specials unless caller explicitly opted in
    local have_devices=false have_specials=false
    for a in "${rsync_args[@]}"; do
        [[ "$a" == "--devices" ]] && have_devices=true
        [[ "$a" == "--specials" ]] && have_specials=true
    done
    if [[ "$have_devices" == false ]]; then
        rsync_args+=("--no-devices")
    fi
    if [[ "$have_specials" == false ]]; then
        rsync_args+=("--no-specials")
    fi
    rsync "${rsync_args[@]}" "$source/" "$dest/"
}

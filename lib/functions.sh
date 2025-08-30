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
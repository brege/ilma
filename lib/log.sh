#!/bin/bash
# lib/log.sh - Operation logging for destructive actions

# Get log directory (create if needed)
get_log_dir() {
    local log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/ilma"
    mkdir -p "$log_dir"
    echo "$log_dir"
}

# Generate log file name with timestamp
get_log_file() {
    local operation="$1"
    local log_dir
    log_dir="$(get_log_dir)"
    local timestamp
    timestamp="$(date '+%Y%m%d_%H%M%S')"
    echo "$log_dir/${operation}_${timestamp}.log"
}

# Initialize log file with header
init_log() {
    local log_file="$1"
    local operation="$2"
    local project_root="$3"

    cat > "$log_file" <<EOF
# ILMA Operation Log
# Operation: $operation
# Project: $(basename "$project_root")
# Directory: $project_root
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# User: $(whoami)
# Host: $(hostname)
# Command: $0 $*

EOF
}

# Log a file operation
log_file_op() {
    local log_file="$1"
    local action="$2"
    local file_path="$3"
    local result="$4"

    local timestamp
    timestamp="$(date '+%H:%M:%S')"

    printf "%s [%s] %s: %s\n" "$timestamp" "$result" "$action" "$file_path" >> "$log_file"
}

# Log a summary line
log_summary() {
    local log_file="$1"
    local message="$2"

    local timestamp
    timestamp="$(date '+%H:%M:%S')"

    printf "%s [INFO] %s\n" "$timestamp" "$message" >> "$log_file"
}

# Show recent log files
show_recent_logs() {
    local log_dir
    log_dir="$(get_log_dir)"

    if [[ ! -d "$log_dir" ]]; then
        echo "No log directory found at: $log_dir"
        return 1
    fi

    local log_files
    mapfile -t log_files < <(find "$log_dir" -name "*.log" -type f -mtime -30 | sort -r)

    if (( ${#log_files[@]} == 0 )); then
        echo "No recent log files found (last 30 days)"
        return 0
    fi

    echo "Recent ILMA operation logs:"
    for log_file in "${log_files[@]}"; do
        local basename_log
        basename_log="$(basename "$log_file")"
        local file_info
        file_info="$(stat -c "%y %s" "$log_file" 2>/dev/null || stat -f "%Sm %z" "$log_file" 2>/dev/null)"
        printf "  %s (%s)\n" "$basename_log" "$file_info"
    done

    echo
    echo "To view a log file: cat \"$log_dir/FILENAME.log\""
}

# Simple utility functions for operation logging
# This is a library file - not meant to be called directly
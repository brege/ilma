#!/bin/bash
# lib/stats.sh - Statistics functions for file analysis

# Count files by pattern from scan output
# Takes JUNK_PATTERNS and JUNK_DIRS arrays from calling context
count_excludes() {
    local -A dir_counts=()
    local -A file_counts=()
    local -A dir_sizes=()
    local -A file_sizes=()
    local total_size=0

    while IFS= read -r path; do
        if [[ -d "$path" ]]; then
            local basename_item
            basename_item="$(basename "$path")"
            local dir_size
            dir_size=$(du -sb "$path" 2>/dev/null | cut -f1)

            # Match against original directory patterns
            for dir_pat in "${JUNK_DIRS[@]}"; do
                if [[ "$basename_item" == "$dir_pat" ]]; then
                    dir_counts["$dir_pat"]=$((${dir_counts["$dir_pat"]:-0} + 1))
                    dir_sizes["$dir_pat"]=$((${dir_sizes["$dir_pat"]:-0} + dir_size))
                    total_size=$((total_size + dir_size))
                    break
                fi
            done
        else
            local basename_item
            basename_item="$(basename "$path")"
            local file_size
            file_size=$(stat -c%s "$path" 2>/dev/null || echo 0)

            # Match against original file patterns
            for file_pat in "${JUNK_PATTERNS[@]}"; do
                if [[ "$basename_item" == "$file_pat" ]]; then
                    file_counts["$file_pat"]=$((${file_counts["$file_pat"]:-0} + 1))
                    file_sizes["$file_pat"]=$((${file_sizes["$file_pat"]:-0} + file_size))
                    total_size=$((total_size + file_size))
                    break
                fi
            done
        fi
    done

    # Output directory stats
    for pattern in "${!dir_counts[@]}"; do
        local size_human
        if command -v numfmt >/dev/null 2>&1; then
            size_human=$(numfmt --to=iec-i --suffix=B "${dir_sizes[$pattern]}" 2>/dev/null || echo "${dir_sizes[$pattern]}B")
        else
            size_human="${dir_sizes[$pattern]}B"
        fi
        echo "  $pattern/: ${dir_counts[$pattern]} directories ($size_human)"
    done

    # Output file stats
    for pattern in "${!file_counts[@]}"; do
        local size_human
        if command -v numfmt >/dev/null 2>&1; then
            size_human=$(numfmt --to=iec-i --suffix=B "${file_sizes[$pattern]}" 2>/dev/null || echo "${file_sizes[$pattern]}B")
        else
            size_human="${file_sizes[$pattern]}B"
        fi
        echo "  $pattern: ${file_counts[$pattern]} files ($size_human)"
    done

    # Total
    if ((total_size > 0)); then
        local total_human
        if command -v numfmt >/dev/null 2>&1; then
            total_human=$(numfmt --to=iec "$total_size" 2>/dev/null || echo "${total_size}B")
        else
            total_human="${total_size}B"
        fi
        echo "Total prunables: $total_human"
    fi
}
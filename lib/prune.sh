#!/bin/bash
# lib/prune.sh - Dry-run pruning functionality for ilma
# ZERO DELETION CODE - Analysis and reporting only

# Source required functions
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

parse_skip_paths_output() {
    local output="$1"
    
    # Skip-paths now outputs structured data by default
    # Just return non-empty lines (the file paths)
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            echo "$line"
        fi
    done <<< "$output"
}

analyze_files() {
    local -a files=("$@")
    local total_size=0
    local file_count=0
    local dir_count=0
    
    echo -e "${YELLOW}=== ANALYSIS REPORT ===${RESET}"
    
    for item in "${files[@]}"; do
        if [[ -d "$item" ]]; then
            echo -e "  ${BLUE}[DIR]${RESET}  $item"
            ((dir_count++))
        elif [[ -f "$item" ]]; then
            local size
            size=$(stat -f%z "$item" 2>/dev/null || stat -c%s "$item" 2>/dev/null || echo "0")
            echo -e "  ${GREEN}[FILE]${RESET} $item ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
            ((total_size += size))
            ((file_count++))
        else
            echo -e "  ${RED}[MISSING]${RESET} $item"
        fi
    done
    
    echo
    echo -e "${YELLOW}Summary:${RESET}"
    echo "  Files: $file_count"
    echo "  Directories: $dir_count"
    echo "  Total size: $(numfmt --to=iec "$total_size" 2>/dev/null || echo "${total_size}B")"
    echo -e "${YELLOW}=== END ANALYSIS ===${RESET}"
}

# Main pruning analysis function - integrates pruner.sh functionality
do_prune() {
    local project_root="$1"
    local verbose="${2:-false}"
    local type="${3:-$TYPE}"
    local project_name
    project_name="$(basename "$project_root")"
    
    echo -e "${BLUE}Prune analysis for: $project_name${RESET}"
    echo -e "${YELLOW}Directory: $project_root${RESET}"
    echo -e "${YELLOW}Type: $type${RESET}"
    echo -e "${RED}DRY RUN ONLY - No files will be deleted${RESET}"
    echo
    
    # Use scan.sh directly (like original pruner.sh)
    local skip_paths_cmd="$ILMA_DIR/lib/scan.sh"
    
    if [[ ! -f "$skip_paths_cmd" ]]; then
        echo -e "${RED}Error: scan.sh not found at $skip_paths_cmd${RESET}"
        return 1
    fi
    
    # Run scan library to get structured data
    local skip_paths_output
    if ! skip_paths_output=$("$skip_paths_cmd" --type "$type" "$project_root" 2>&1); then
        echo -e "${RED}Error: scan analysis failed${RESET}"
        return 1
    fi
    
    # In verbose mode, also show the pretty output
    local pretty_output=""
    if [[ "$verbose" == "true" ]]; then
        pretty_output=$("$skip_paths_cmd" --type "$type" --pretty "$project_root" 2>&1) || true
    fi
    
    # Parse the output to extract files to analyze
    local files_to_analyze=()
    mapfile -t files_to_analyze < <(parse_skip_paths_output "$skip_paths_output")
    
    if (( ${#files_to_analyze[@]} == 0 )); then
        echo -e "${GREEN}No junk files found - project appears clean!${RESET}"
        return 0
    fi
    
    echo -e "${RED}Found ${#files_to_analyze[@]} junk items${RESET}"
    echo
    
    # Show detailed output in verbose mode
    if [[ "$verbose" == "true" ]]; then
        echo "=== Skip-paths detailed output ==="
        echo "$pretty_output"
        echo "=================================="
        echo
        analyze_files "${files_to_analyze[@]}"
    else
        # Just show count and first few items as preview
        local preview_count=$((${#files_to_analyze[@]} < 5 ? ${#files_to_analyze[@]} : 5))
        echo -e "${YELLOW}Preview (first $preview_count items):${RESET}"
        for ((i=0; i<preview_count; i++)); do
            local item="${files_to_analyze[i]}"
            local relative_path
            relative_path="$(realpath --relative-to="$project_root" "$item" 2>/dev/null || basename "$item")"
            
            if [[ -d "$item" ]]; then
                echo -e "  ${YELLOW}DIR:${RESET}  $relative_path/"
            else
                echo -e "  ${RED}FILE:${RESET} $relative_path"
            fi
        done
        
        if (( ${#files_to_analyze[@]} > 5 )); then
            echo -e "  ${BLUE}... and $((${#files_to_analyze[@]} - 5)) more items${RESET}"
        fi
        
        echo
        echo -e "${YELLOW}Use --verbose to see detailed analysis with file sizes${RESET}"
    fi
    
    echo -e "${YELLOW}NOTE: This is a dry-run analysis only. No files were deleted.${RESET}"
}

# If called directly as a command (for standalone testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # This would be the prune command entry point
    PROJECT_ROOT="${1:-$(pwd)}"
    TYPE="${2:-minimal}"
    VERBOSE="${3:-false}"
    
    # Load configuration first
    source "$ILMA_DIR/lib/config.sh"
    load_config "$PROJECT_ROOT" "$TYPE"
    
    # Perform prune analysis
    do_prune "$PROJECT_ROOT" "$VERBOSE"
fi

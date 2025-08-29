#!/usr/bin/env bash
# pruner.sh - A dry-run only pruner that interfaces with skip-paths library
# ZERO DELETION CODE - Analysis and reporting only

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
SKIP_PATHS_LIB="$SCRIPT_DIR/lib/skip-paths.sh"

# Default settings - ALWAYS dry run
TYPE="minimal"
DIR="."
VERBOSE=false

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [directory]

A dry-run only pruner that interfaces with the skip-paths library to identify
junk files from projects. NO DELETION CAPABILITY - ANALYSIS ONLY.

OPTIONS:
  --type TYPE        Project type to use (passed to skip-paths)
  --verbose          Show detailed output
  -h, --help         Show this help

DIRECTORY:
  directory          Directory to scan (default: current directory)

EXAMPLES:
  $0                                    # Analyze current directory
  $0 --type latex /path/to/project     # Analyze with LaTeX type
  $0 --verbose --type latex ./docs     # Verbose analysis
  
NOTE: This tool only analyzes and reports. No files are ever deleted.
EOF
    exit 1
}

log_info() {
    echo -e "${BLUE}[INFO]${RESET} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${RESET} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $*"
}

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

main() {
    # Parse arguments
    while (( $# )); do
        case "$1" in
            --type)
                if [[ -z "${2:-}" ]]; then
                    log_error "--type requires an argument"
                    usage
                fi
                TYPE="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                DIR="$1"
                shift
                ;;
        esac
    done
    
    # Check if skip-paths library exists
    if [[ ! -f "$SKIP_PATHS_LIB" ]]; then
        log_error "Skip-paths library not found: $SKIP_PATHS_LIB"
        exit 1
    fi
    
    # Make sure directory exists
    if [[ ! -d "$DIR" ]]; then
        log_error "Directory does not exist: $DIR"
        exit 1
    fi
    
    log_info "Pruner Analysis Starting..."
    log_info "Mode: DRY RUN ONLY (no deletion capability)"
    log_info "Type: $TYPE"
    log_info "Directory: $DIR"
    echo
    
    # Run skip-paths library to get structured data
    log_info "Running skip-paths analysis..."
    skip_paths_output=$("$SKIP_PATHS_LIB" --type "$TYPE" "$DIR" 2>&1) || {
        log_error "Skip-paths analysis failed"
        exit 1
    }
    
    # In verbose mode, also show the pretty output
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Getting detailed output for verbose mode..."
        pretty_output=$("$SKIP_PATHS_LIB" --type "$TYPE" --pretty "$DIR" 2>&1) || true
    fi
    
    # Show the detailed output in verbose mode
    if [[ "$VERBOSE" == "true" ]]; then
        echo "=== Skip-paths detailed output ==="
        echo "$pretty_output"
        echo "=================================="
        echo
    fi
    
    # Parse the output to extract files to analyze
    mapfile -t files_to_analyze < <(parse_skip_paths_output "$skip_paths_output")
    
    if (( ${#files_to_analyze[@]} == 0 )); then
        log_info "No junk files identified for cleanup."
        exit 0
    fi
    
    log_info "Found ${#files_to_analyze[@]} items that could be cleaned up"
    echo
    
    analyze_files "${files_to_analyze[@]}"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/usr/bin/env bash
# commands/scan.sh - General-purpose dry-run skip printer with LaTeX-style project detection

set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh"
initialize_paths

source "$ILMA_DIR/lib/configs.sh"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

declare -A types_map=()
TYPE=""
DIR="."
PRETTY_OUTPUT=false
STATS_MODE=""

usage() {
    cat <<EOF
Usage: ilma scan [--type TYPE] [--pretty] [directory]

  --type TYPE     Project type (required if no local .ilma.conf). 
                  Supported: 
                    ${!types_map[*]} all
  --pretty        Human-friendly output
  directory       Directory to scan (default: current dir)

Outputs junk file paths based on the selected type or local .ilma.conf.
EOF
    exit 1
}

add_types_from_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return
    while IFS= read -r -d '' cf; do
        local basefile
        basefile="$(basename "$cf")"
        local name="${basefile%.ilma.conf}"
        types_map["$name"]="$cf"
    done < <(find "$dir" -maxdepth 1 -type f -name '*.ilma.conf' -print0 | sort -z)
}

initialize_types_map() {
    types_map=()
    if builtin_dir="$(get_ilma_builtin_projects_dir)"; then
        add_types_from_dir "$builtin_dir"
    fi
    if user_dir="$(get_ilma_user_projects_dir)" && [[ -n "$user_dir" ]]; then
        add_types_from_dir "$user_dir"
    fi
}

parse_scan_arguments() {
    TYPE=""
    DIR="."
    PRETTY_OUTPUT=false
    STATS_MODE=""

    while (( $# )); do
        case "$1" in
            --type)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --type requires an argument" >&2
                    usage
                fi
                TYPE="$2"
                shift 2
                ;;
            --pretty)
                PRETTY_OUTPUT=true
                shift
                ;;
            --stats=*)
                STATS_MODE="${1#--stats=}"
                shift
                ;;
            -h|--help)
                usage
                ;;
            --*)
                echo "Error: Unknown option '$1'" >&2
                usage
                ;;
            *)
                DIR="$1"
                shift
                ;;
        esac
    done
}

CONFIG_FILE=""
RSYNC_EXCLUDES=()

scan_main() {
    initialize_types_map
    parse_scan_arguments "$@"

    DIR="$(require_project_root "$DIR")"

    CONFIG_FILE=""
    RSYNC_EXCLUDES=()

    if [[ -z "$TYPE" ]]; then
        if [[ -f "$DIR/.ilma.conf" ]]; then
            source "$DIR/.ilma.conf"
            CONFIG_FILE="$DIR/.ilma.conf (local)"
        else
            echo -e "${RED}Error:${RESET} --type is required when no local .ilma.conf found"
            echo "Supported types: ${!types_map[*]} all"
            exit 1
        fi
    elif [[ "$TYPE" == "all" || "$TYPE" =~ \| ]]; then
        if [[ "$TYPE" == "all" ]]; then
            CONFIG_FILE="all project configs"
            for config_path in "${types_map[@]}"; do
                if [[ "$(basename "$config_path")" =~ -project\.ilma\.conf$ ]]; then
                    source "$config_path"
                fi
            done
        else
            IFS='|' read -ra TYPES <<< "$TYPE"
            CONFIG_FILE="multiple types: ${TYPES[*]}"
            for single_type in "${TYPES[@]}"; do
                if [[ -z "${types_map[$single_type]:-}" ]]; then
                    echo -e "${RED}Error:${RESET} Unsupported type '$single_type'"
                    echo "Supported types: ${!types_map[*]} all"
                    exit 1
                fi
                source "${types_map[$single_type]}"
            done
        fi
    elif [[ -z "${types_map[$TYPE]:-}" ]]; then
        echo -e "${RED}Error:${RESET} Unsupported type '$TYPE'"
        echo "Supported types: ${!types_map[*]} all"
        exit 1
    else
        CONFIG_FILE="${types_map[$TYPE]}"
        source "$CONFIG_FILE"
    fi

    JUNK_PATTERNS=()
    JUNK_DIRS=()
    for exclude in "${RSYNC_EXCLUDES[@]}"; do
        if [[ "$exclude" == "--exclude" ]]; then
            continue
        fi
        pattern="${exclude#\'}"
        pattern="${pattern%\'}"
        pattern="${pattern#\"}"
        pattern="${pattern%\"}"
        pattern="${exclude%/}"
        if [[ "$exclude" == */ ]]; then
            JUNK_DIRS+=("$pattern")
        else
            JUNK_PATTERNS+=("$pattern")
        fi
    done

    if [[ "$PRETTY_OUTPUT" == "true" ]]; then
        echo -e "${BLUE}Skip analysis for type '$TYPE' in directory: $DIR${RESET}"
        echo -e "${YELLOW}Dry run mode: no files will be deleted${RESET}"
        echo
    fi

    project_dirs=("$DIR")

    if [[ ! -d "$DIR" ]]; then
        if [[ "$PRETTY_OUTPUT" == "true" ]]; then
            echo "Directory not found: $DIR"
        fi
        exit 1
    fi

    BACKUP_DIRS=(backup)
    ALL_PRUNE_DIRS=("${JUNK_DIRS[@]}")
    for dir in "${BACKUP_DIRS[@]}"; do
        ALL_PRUNE_DIRS+=("$dir")
    done
    ALL_PRUNE_DIRS+=("*.bak")

    PRUNE_EXPR=""
    for pd in "${ALL_PRUNE_DIRS[@]}"; do
        [[ -n "$PRUNE_EXPR" ]] && PRUNE_EXPR+=" -o "
        PRUNE_EXPR+="-name $pd"
    done

    for proj_dir in "${project_dirs[@]}"; do
        if [[ "$PRETTY_OUTPUT" == "true" ]]; then
            echo -e "${GREEN}Project directory: $proj_dir${RESET}"
        fi
        all_junk=()

        for pat in "${JUNK_PATTERNS[@]}"; do
            while IFS= read -r -d '' f; do
                all_junk+=("$f")
            done < <(find "$proj_dir" \( $PRUNE_EXPR \) -prune -false -o -type f -name "$pat" -print0 2>/dev/null || true)
        done

        for dir_pat in "${JUNK_DIRS[@]}"; do
            while IFS= read -r -d '' d; do
                all_junk+=("$d/")
            done < <(find "$proj_dir" \( $PRUNE_EXPR \) -prune -false -o -type d -name "$dir_pat" -print0 2>/dev/null || true)
        done

        if (( ${#all_junk[@]} > 0 )); then
            if [[ "$STATS_MODE" == "excludes" ]]; then
                source "$ILMA_DIR/lib/stats.sh"
                echo -e "${RED}Found prunables:${RESET}"
                for item in "${all_junk[@]}"; do
                    echo "$item"
                done | count_excludes
            elif [[ "$PRETTY_OUTPUT" == "true" ]]; then
                echo -e "  ${RED}WOULD DELETE:${RESET}"
                for item in "${all_junk[@]}"; do
                    echo "    $item"
                done
            else
                for item in "${all_junk[@]}"; do
                    echo "$item"
                done
            fi
        else
            if [[ "$PRETTY_OUTPUT" == "true" ]]; then
                echo "  No junk files found."
            fi
        fi

        if [[ "$PRETTY_OUTPUT" == "true" ]]; then
            echo
        fi
    done

    if [[ "$PRETTY_OUTPUT" == "true" ]]; then
        echo -e "${YELLOW}Dry run complete: no files deleted${RESET}"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    scan_main "$@"
fi

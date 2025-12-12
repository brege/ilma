#!/bin/bash
# commands/validate_modular.sh - Modular validation orchestrator

set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_template.sh"
template_initialize_paths

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

usage() {
    cat <<EOF
Usage: ilma validate [OPTIONS] [PROJECT_PATH]

Validate ilma system components and configuration.

OPTIONS:
  --dependencies  Validate all system dependencies
  --gpg           Validate GPG configuration and keys
  --compression   Validate compression tools
  --config        Validate basic configuration
  --paths         Validate local paths and permissions
  --remote        Validate remote connectivity
  --basic         Basic validation (config, paths, compression, gpg) (default)
  --full          Full validation including remote connectivity

ARGUMENTS:
  PROJECT_PATH Path to project directory (default: current directory)

Examples:
  ilma validate                    # Validate all components
  ilma validate --dependencies     # Check system dependencies only
  ilma validate --gpg              # Check GPG setup only
EOF
}

parse_validate_arguments() {
    VALIDATION_MODE="basic"
    PROJECT_ROOT="$(pwd)"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dependencies) VALIDATION_MODE="dependencies"; shift ;;
            --gpg) VALIDATION_MODE="gpg"; shift ;;
            --compression) VALIDATION_MODE="compression"; shift ;;
            --config) VALIDATION_MODE="config"; shift ;;
            --paths) VALIDATION_MODE="paths"; shift ;;
            --remote) VALIDATION_MODE="remote"; shift ;;
            --basic) VALIDATION_MODE="basic"; shift ;;
            --full) VALIDATION_MODE="full"; shift ;;
            -h|--help) usage; exit 0 ;;
            -*)
                echo "Error: Unknown option $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                PROJECT_ROOT="$1"
                shift
                ;;
        esac
    done
}

format_output() {
    while IFS= read -r line; do
        case "$line" in
            SECTION:*)
                section="${line#SECTION:}"
                echo -e "\n${BLUE}=== $section ===${RESET}"
                ;;
            PASS:*)
                message="${line#PASS:}"
                echo -e "${GREEN}✓${RESET} $message"
                ;;
            FAIL:*)
                rest="${line#FAIL:}"
                if [[ "$rest" == *:* ]]; then
                    title="${rest%%:*}"
                    error="${rest#*:}"
                    echo -e "${RED}✗${RESET} $title"
                    echo -e "  ${RED}Error:${RESET} $error"
                else
                    echo -e "${RED}✗${RESET} $rest"
                fi
                ;;
            WARN:*)
                rest="${line#WARN:}"
                if [[ "$rest" == *:* ]]; then
                    title="${rest%%:*}"
                    warning="${rest#*:}"
                    echo -e "${YELLOW}!${RESET} $title"
                    echo -e "  ${YELLOW}Warning:${RESET} $warning"
                else
                    echo -e "${YELLOW}!${RESET} $rest"
                fi
                ;;
            INFO:*)
                message="${line#INFO:}"
                echo -e "${BLUE}i${RESET} $message"
                ;;
            SUMMARY:PASS:*)
                message="${line#SUMMARY:PASS:}"
                echo -e "\n${GREEN}$message${RESET}"
                ;;
            SUMMARY:FAIL:*)
                message="${line#SUMMARY:FAIL:}"
                echo -e "\n${RED}$message${RESET}"
                ;;
        esac
    done
}

validate_main() {
    parse_validate_arguments "$@"
    PROJECT_ROOT="$(template_require_project_root "$PROJECT_ROOT")"

    if [[ -f "$PROJECT_ROOT/.ilma.conf" ]]; then
        source "$PROJECT_ROOT/.ilma.conf" 2>/dev/null || true
    fi

    case "$VALIDATION_MODE" in
        dependencies)
            "$ILMA_DIR/lib/validation/dependencies.sh" | format_output
            ;;
        gpg)
            GPG_KEY_ID="${GPG_KEY_ID:-}" "$ILMA_DIR/lib/validation/gpg.sh" | format_output
            ;;
        compression)
            COMPRESSION_TYPE="${COMPRESSION_TYPE:-}" "$ILMA_DIR/lib/validation/compression.sh" | format_output
            ;;
        config)
            "$ILMA_DIR/lib/validation/config.sh" "$PROJECT_ROOT" | format_output
            ;;
        paths)
            "$ILMA_DIR/lib/validation/paths.sh" "$PROJECT_ROOT" | format_output
            ;;
        remote)
            "$ILMA_DIR/lib/validation/remote.sh" "$PROJECT_ROOT" | format_output
            "$ILMA_DIR/lib/validation/manifests.sh" | format_output
            ;;
        basic)
            echo -e "${BLUE}ilma Configuration Validator${RESET}"
            echo "Project: $PROJECT_ROOT"
            echo "Validation level: basic"

            "$ILMA_DIR/lib/validation/config.sh" "$PROJECT_ROOT" | format_output
            "$ILMA_DIR/lib/validation/paths.sh" "$PROJECT_ROOT" | format_output
            COMPRESSION_TYPE="${COMPRESSION_TYPE:-}" "$ILMA_DIR/lib/validation/compression.sh" | format_output
            GPG_KEY_ID="${GPG_KEY_ID:-}" "$ILMA_DIR/lib/validation/gpg.sh" | format_output
            ;;
        full)
            echo -e "${BLUE}ilma Configuration Validator${RESET}"
            echo "Project: $PROJECT_ROOT"
            echo "Validation level: full"

            "$ILMA_DIR/lib/validation/config.sh" "$PROJECT_ROOT" | format_output
            "$ILMA_DIR/lib/validation/paths.sh" "$PROJECT_ROOT" | format_output
            COMPRESSION_TYPE="${COMPRESSION_TYPE:-}" "$ILMA_DIR/lib/validation/compression.sh" | format_output
            GPG_KEY_ID="${GPG_KEY_ID:-}" "$ILMA_DIR/lib/validation/gpg.sh" | format_output
            "$ILMA_DIR/lib/validation/remote.sh" "$PROJECT_ROOT" | format_output
            "$ILMA_DIR/lib/validation/manifests.sh" | format_output
            "$ILMA_DIR/lib/validation/dependencies.sh" | format_output
            ;;
        *)
            echo "Error: Unknown validation mode '$VALIDATION_MODE'" >&2
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    template_dispatch usage validate_main "$@"
fi

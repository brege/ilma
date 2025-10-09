#!/bin/bash
# lib/validation/config.sh - Basic configuration validation

PROJECT_ROOT="${1:-$(pwd)}"

echo "SECTION:Basic Configuration"

# Check if project directory exists and is accessible
if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "FAIL:Project directory accessibility:Directory '$PROJECT_ROOT' does not exist"
    exit 1
fi
echo "PASS:Project directory accessibility"

# Check for configuration files
config_found=false
if [[ -f "$PROJECT_ROOT/.ilma.conf" ]]; then
    config_found=true
    echo "PASS:Configuration file found"
fi

if [[ "$config_found" == false ]]; then
    echo "INFO:No project config (.ilma.conf) - using global defaults"
fi

# Load project config to check PROJECT_TYPE
if [[ -f "$PROJECT_ROOT/.ilma.conf" ]]; then
    source "$PROJECT_ROOT/.ilma.conf" 2>/dev/null || true
fi

# Validate PROJECT_TYPE if specified
if [[ -n "${PROJECT_TYPE:-}" ]]; then
    SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    ILMA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

    type_config="$ILMA_DIR/configs/projects/${PROJECT_TYPE}.ilma.conf"
    if [[ -f "$type_config" ]]; then
        echo "PASS:PROJECT_TYPE inheritance ($PROJECT_TYPE)"
    else
        echo "FAIL:PROJECT_TYPE inheritance:Type config for '$PROJECT_TYPE' not found"
    fi
fi

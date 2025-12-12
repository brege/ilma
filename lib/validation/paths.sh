#!/bin/bash
# lib/validation/paths.sh - Local paths and permissions validation

PROJECT_ROOT="${1:-$(pwd)}"

echo "SECTION:Local Paths & Permissions"

# Load configuration from config.ini and project config
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ILMA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$ILMA_DIR/lib/configs.sh"

# Load from config.ini
config_path=""
if config_path="$(get_ilma_global_config_path)"; then
    BACKUP_BASE_DIR=$(grep -E '^\s*backup_base_dir\s*=' "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
    ARCHIVE_BASE_DIR=$(grep -E '^\s*archive_base_dir\s*=' "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
fi

# Load from project config (overrides)
if [[ -f "$PROJECT_ROOT/.ilma.conf" ]]; then
    source "$PROJECT_ROOT/.ilma.conf" 2>/dev/null || true
fi

# Check backup directory
if [[ -n "$BACKUP_BASE_DIR" ]]; then
    if [[ "$BACKUP_BASE_DIR" == "." ]]; then
        backup_dir="$PROJECT_ROOT"
    else
        backup_dir="$BACKUP_BASE_DIR"
    fi

    if [[ -d "$backup_dir" ]]; then
        if [[ -w "$backup_dir" ]]; then
            echo "PASS:Backup directory writable ($backup_dir)"
        else
            echo "FAIL:Backup directory permissions:Directory '$backup_dir' not writable"
        fi
    else
        echo "WARN:Backup directory:Directory '$backup_dir' does not exist (will be created)"
    fi
else
    echo "WARN:Backup directory:BACKUP_BASE_DIR not configured"
fi

# Check archive directory
if [[ -n "$ARCHIVE_BASE_DIR" ]]; then
    if [[ -d "$ARCHIVE_BASE_DIR" ]]; then
        if [[ -w "$ARCHIVE_BASE_DIR" ]]; then
            echo "PASS:Archive directory writable ($ARCHIVE_BASE_DIR)"
        else
            echo "FAIL:Archive directory permissions:Directory '$ARCHIVE_BASE_DIR' not writable"
        fi
    else
        echo "WARN:Archive directory:Directory '$ARCHIVE_BASE_DIR' does not exist (will be created)"
    fi
fi

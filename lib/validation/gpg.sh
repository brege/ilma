#!/bin/bash
# lib/validation/gpg.sh - GPG system validation

echo "SECTION:GPG Configuration"

if command -v gpg >/dev/null 2>&1; then
    echo "PASS:GPG executable"

    # Load GPG_KEY_ID from config.ini if not already set
    if [[ -z "${GPG_KEY_ID:-}" ]]; then
        SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
        ILMA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
        source "$ILMA_DIR/lib/configs.sh"
        config_path=""
        if config_path="$(get_ilma_global_config_path)"; then
            GPG_KEY_ID=$(grep -E '^\s*key_id\s*=' "$config_path" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
        fi
    fi

    if [[ -n "${GPG_KEY_ID:-}" ]]; then
        if gpg --list-secret-keys "$GPG_KEY_ID" >/dev/null 2>&1; then
            echo "PASS:GPG key available ($GPG_KEY_ID)"
        else
            echo "FAIL:GPG key:Key '$GPG_KEY_ID' not found in keyring"
        fi
    else
        echo "INFO:No GPG key configured (GPG_KEY_ID not set)"
    fi
else
    echo "FAIL:GPG executable:gpg command not found"
fi

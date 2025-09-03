#!/bin/bash
# lib/validation/remote.sh - Remote connectivity validation

echo "SECTION:Remote Connectivity"

# Load configuration from config.ini
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
ILMA_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [[ -f "$ILMA_DIR/config.ini" ]]; then
    REMOTE_SERVER=$(grep -E '^\s*remote_server\s*=' "$ILMA_DIR/config.ini" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
    REMOTE_PATH=$(grep -E '^\s*remote_path\s*=' "$ILMA_DIR/config.ini" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
fi

# Override with project config if it exists
PROJECT_ROOT="${1:-$(pwd)}"
if [[ -f "$PROJECT_ROOT/.ilma.conf" ]]; then
    source "$PROJECT_ROOT/.ilma.conf" 2>/dev/null || true
fi

if [[ -n "$REMOTE_SERVER" ]]; then
    echo "INFO:Testing connectivity to $REMOTE_SERVER..."

    # Test SSH connectivity
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" exit 2>/dev/null; then
        echo "PASS:SSH connectivity to $REMOTE_SERVER"

        # Test remote path if specified
        if [[ -n "$REMOTE_PATH" ]]; then
            if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" "test -d '$REMOTE_PATH'" 2>/dev/null; then
                echo "PASS:Remote path accessible ($REMOTE_PATH)"

                # Test write permissions
                if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" "test -w '$REMOTE_PATH'" 2>/dev/null; then
                    echo "PASS:Remote path writable"
                else
                    echo "FAIL:Remote permissions:Remote path '$REMOTE_PATH' not writable"
                fi
            else
                echo "FAIL:Remote path:Remote path '$REMOTE_PATH' not accessible"
            fi
        else
            echo "WARN:Remote path:REMOTE_PATH not configured"
        fi

        # Test rsync availability on remote
        if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" "command -v rsync" &>/dev/null; then
            echo "PASS:Remote rsync availability"
        else
            echo "FAIL:Remote rsync:rsync not found on remote server"
        fi

    else
        echo "FAIL:SSH connectivity:Cannot connect to $REMOTE_SERVER"
    fi

    # Test local rsync
    if command -v rsync >/dev/null 2>&1; then
        echo "PASS:Local rsync availability"
    else
        echo "FAIL:Local rsync:rsync not found in local PATH"
    fi
else
    echo "INFO:Remote sync disabled (REMOTE_SERVER not set)"
fi
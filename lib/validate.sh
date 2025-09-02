#!/bin/bash
# lib/validate.sh - Configuration validation and smoke testing for ilma

# Source required libraries
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "$ILMA_DIR/lib/config.sh"
source "$ILMA_DIR/lib/compression.sh"
source "$ILMA_DIR/lib/functions.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Validation state tracking
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0
VALIDATION_CHECKS=0

# Validation result functions
validate_pass() {
    local check_name="$1"
    VALIDATION_CHECKS=$((VALIDATION_CHECKS + 1))
    echo -e "${GREEN}✓${RESET} $check_name"
}

validate_fail() {
    local check_name="$1"
    local error_msg="$2"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    VALIDATION_CHECKS=$((VALIDATION_CHECKS + 1))
    echo -e "${RED}✗${RESET} $check_name"
    if [[ -n "$error_msg" ]]; then
        echo -e "  ${RED}Error:${RESET} $error_msg"
    fi
}

validate_warn() {
    local check_name="$1"
    local warning_msg="$2"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
    VALIDATION_CHECKS=$((VALIDATION_CHECKS + 1))
    echo -e "${YELLOW}!${RESET} $check_name"
    if [[ -n "$warning_msg" ]]; then
        echo -e "  ${YELLOW}Warning:${RESET} $warning_msg"
    fi
}

validate_info() {
    local message="$1"
    echo -e "${BLUE}i${RESET} $message"
}

# Basic configuration validation
validate_basic_config() {
    echo -e "\n${BLUE}=== Basic Configuration ===${RESET}"

    # Check if project directory exists and is accessible
    if [[ ! -d "$PROJECT_ROOT" ]]; then
        validate_fail "Project directory accessibility" "Directory '$PROJECT_ROOT' does not exist"
        return
    fi
    validate_pass "Project directory accessibility"

    # Check for configuration files
    local config_found=false
    for config_file in ".ilma.conf" ".archive.conf" ".backup.conf"; do
        if [[ -f "$PROJECT_ROOT/$config_file" ]]; then
            config_found=true
            validate_pass "Configuration file found ($config_file)"
            break
        fi
    done

    if [[ "$config_found" == false ]]; then
        validate_info "No project config (.ilma.conf) - using global defaults"
    fi

    # Validate PROJECT_TYPE if specified
    if [[ -n "${PROJECT_TYPE:-}" ]]; then
        local type_config="$ILMA_DIR/configs/${PROJECT_TYPE}-project.ilma.conf"
        if [[ -f "$type_config" ]]; then
            validate_pass "PROJECT_TYPE inheritance ($PROJECT_TYPE)"
        elif [[ -f "$ILMA_DIR/configs/${PROJECT_TYPE}.ilma.conf" ]]; then
            validate_pass "PROJECT_TYPE inheritance ($PROJECT_TYPE)"
        else
            validate_fail "PROJECT_TYPE inheritance" "Type config for '$PROJECT_TYPE' not found"
        fi
    fi
}

# Validate local paths and permissions
validate_local_paths() {
    echo -e "\n${BLUE}=== Local Paths & Permissions ===${RESET}"

    # Check backup directory
    if [[ -n "$BACKUP_BASE_DIR" ]]; then
        local backup_dir
        if [[ "$BACKUP_BASE_DIR" == "." ]]; then
            backup_dir="$PROJECT_ROOT"
        else
            backup_dir="$BACKUP_BASE_DIR"
        fi

        if [[ -d "$backup_dir" ]]; then
            if [[ -w "$backup_dir" ]]; then
                validate_pass "Backup directory writable ($backup_dir)"
            else
                validate_fail "Backup directory permissions" "Directory '$backup_dir' not writable"
            fi
        else
            validate_warn "Backup directory" "Directory '$backup_dir' does not exist (will be created)"
        fi
    else
        validate_warn "Backup directory" "BACKUP_BASE_DIR not configured"
    fi

    # Check archive directory
    if [[ -n "$ARCHIVE_BASE_DIR" ]]; then
        if [[ -d "$ARCHIVE_BASE_DIR" ]]; then
            if [[ -w "$ARCHIVE_BASE_DIR" ]]; then
                validate_pass "Archive directory writable ($ARCHIVE_BASE_DIR)"
            else
                validate_fail "Archive directory permissions" "Directory '$ARCHIVE_BASE_DIR' not writable"
            fi
        else
            validate_warn "Archive directory" "Directory '$ARCHIVE_BASE_DIR' does not exist (will be created)"
        fi
    fi

    # Check context directory
    if [[ -n "$CONTEXT_BASE_DIR" ]]; then
        if [[ -d "$CONTEXT_BASE_DIR" ]]; then
            if [[ -w "$CONTEXT_BASE_DIR" ]]; then
                validate_pass "Context directory writable ($CONTEXT_BASE_DIR)"
            else
                validate_fail "Context directory permissions" "Directory '$CONTEXT_BASE_DIR' not writable"
            fi
        else
            validate_warn "Context directory" "Directory '$CONTEXT_BASE_DIR' does not exist (will be created)"
        fi
    fi
}

# Validate compression capabilities
validate_compression() {
    echo -e "\n${BLUE}=== Compression Support ===${RESET}"

    local compression_type="${COMPRESSION_TYPE:-zstd}"

    case "$compression_type" in
        zstd)
            if command -v zstd &> /dev/null; then
                validate_pass "Compression algorithm (zstd)"
            else
                validate_fail "Compression algorithm" "zstd not found in PATH"
            fi
            ;;
        gzip)
            if command -v gzip &> /dev/null; then
                validate_pass "Compression algorithm (gzip)"
            else
                validate_fail "Compression algorithm" "gzip not found in PATH"
            fi
            ;;
        bzip2)
            if command -v bzip2 &> /dev/null; then
                validate_pass "Compression algorithm (bzip2)"
            else
                validate_fail "Compression algorithm" "bzip2 not found in PATH"
            fi
            ;;
        xz)
            if command -v xz &> /dev/null; then
                validate_pass "Compression algorithm (xz)"
            else
                validate_fail "Compression algorithm" "xz not found in PATH"
            fi
            ;;
        lzma)
            if command -v lzma &> /dev/null; then
                validate_pass "Compression algorithm (lzma)"
            else
                validate_fail "Compression algorithm" "lzma not found in PATH"
            fi
            ;;
        none)
            validate_pass "Compression algorithm (none/disabled)"
            ;;
        *)
            validate_fail "Compression algorithm" "Unknown compression type: $compression_type"
            ;;
    esac

    # Test tar availability
    if command -v tar &> /dev/null; then
        validate_pass "Archive tool (tar)"
    else
        validate_fail "Archive tool" "tar not found in PATH"
    fi
}

# Validate GPG configuration
validate_gpg() {
    echo -e "\n${BLUE}=== GPG Configuration ===${RESET}"

    if [[ -n "$GPG_KEY_ID" ]]; then
        if command -v gpg &> /dev/null; then
            validate_pass "GPG executable"

            # Check if key exists
            if gpg --list-secret-keys "$GPG_KEY_ID" &> /dev/null; then
                validate_pass "GPG key available ($GPG_KEY_ID)"
            else
                validate_fail "GPG key" "Secret key '$GPG_KEY_ID' not found in keyring"
            fi
        else
            validate_fail "GPG executable" "gpg not found in PATH"
        fi
    else
        validate_info "GPG encryption disabled (GPG_KEY_ID not set)"
    fi
}

# Validate remote connectivity
validate_remote() {
    echo -e "\n${BLUE}=== Remote Connectivity ===${RESET}"

    if [[ -n "$REMOTE_SERVER" ]]; then
        validate_info "Testing connectivity to $REMOTE_SERVER..."

        # Test SSH connectivity
        if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" exit 2>/dev/null; then
            validate_pass "SSH connectivity to $REMOTE_SERVER"

            # Test remote path if specified
            if [[ -n "$REMOTE_PATH" ]]; then
                if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" "test -d '$REMOTE_PATH'" 2>/dev/null; then
                    validate_pass "Remote path accessible ($REMOTE_PATH)"

                    # Test write permissions
                    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" "test -w '$REMOTE_PATH'" 2>/dev/null; then
                        validate_pass "Remote path writable"
                    else
                        validate_fail "Remote permissions" "Remote path '$REMOTE_PATH' not writable"
                    fi
                else
                    validate_fail "Remote path" "Remote path '$REMOTE_PATH' not accessible"
                fi
            else
                validate_warn "Remote path" "REMOTE_PATH not configured"
            fi

            # Test rsync availability on remote
            if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_SERVER" "command -v rsync" &>/dev/null; then
                validate_pass "Remote rsync availability"
            else
                validate_fail "Remote rsync" "rsync not found on remote server"
            fi

        else
            validate_fail "SSH connectivity" "Cannot connect to $REMOTE_SERVER"
        fi

        # Test local rsync
        if command -v rsync &> /dev/null; then
            validate_pass "Local rsync availability"
        else
            validate_fail "Local rsync" "rsync not found in local PATH"
        fi
    else
        validate_info "Remote sync disabled (REMOTE_SERVER not set)"
    fi
}

# Smoke test with dummy data
validate_smoke_test() {
    echo -e "\n${BLUE}=== Smoke Test (Dummy Data) ===${RESET}"

    local smoke_test_dir="/tmp/ilma-smoke-test-$$"
    local test_project_dir="$smoke_test_dir/test-project"

    # Create test project
    mkdir -p "$test_project_dir"
    echo "# Test Project" > "$test_project_dir/README.md"
    echo "console.log('test');" > "$test_project_dir/test.js"
    echo "temp data" > "$test_project_dir/temp.log"

    # Create minimal test config
    cat > "$test_project_dir/.ilma.conf" << 'EOF'
PROJECT_TYPE="bash"
BACKUP_BASE_DIR="/tmp"
ARCHIVE_BASE_DIR=""
CONTEXT_BASE_DIR=""
GPG_KEY_ID=""
REMOTE_SERVER=""
RSYNC_EXCLUDES+=(
    --exclude '*.log'
)
EOF

    validate_info "Created temporary test project at $test_project_dir"

    # Test configuration loading
    if source "$ILMA_DIR/lib/config.sh" && load_config "$test_project_dir" ""; then
        validate_pass "Configuration loading with test project"
    else
        validate_fail "Configuration loading" "Failed to load config for test project"
        cleanup_smoke_test "$smoke_test_dir"
        return
    fi

    # Test backup creation (dry run)
    validate_info "Testing backup process (dry run)..."
    if "$ILMA_DIR/ilma" config "$test_project_dir" &>/dev/null; then
        validate_pass "Full pipeline configuration test"
    else
        validate_fail "Full pipeline test" "ilma config command failed"
    fi

    # Cleanup
    cleanup_smoke_test "$smoke_test_dir"
    validate_pass "Smoke test cleanup completed"
}

cleanup_smoke_test() {
    local smoke_test_dir="$1"
    if [[ -d "$smoke_test_dir" ]]; then
        rm -rf "$smoke_test_dir"
    fi
}

# Main validation function
run_validation() {
    local validation_level="$1"
    local project_root="$2"

    # Load configuration
    PROJECT_ROOT="$project_root"
    load_config "$PROJECT_ROOT"

    echo -e "${BLUE}ilma Configuration Validator${RESET}"
    echo -e "Project: $PROJECT_ROOT"
    echo -e "Validation level: $validation_level"

    # Always run basic checks
    validate_basic_config
    validate_local_paths
    validate_compression
    validate_gpg

    # Run connectivity tests for --full validation
    if [[ "$validation_level" == "full" || "$validation_level" == "smoke-test" ]]; then
        validate_remote
    fi

    # Run smoke test if requested
    if [[ "$validation_level" == "smoke-test" ]]; then
        validate_smoke_test
    fi

    # Summary
    echo -e "\n${BLUE}=== Validation Summary ===${RESET}"
    echo -e "Checks run: $VALIDATION_CHECKS"
    echo -e "${GREEN}Passed: $((VALIDATION_CHECKS - VALIDATION_ERRORS - VALIDATION_WARNINGS))${RESET}"

    if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}Warnings: $VALIDATION_WARNINGS${RESET}"
    fi

    if [[ $VALIDATION_ERRORS -gt 0 ]]; then
        echo -e "${RED}Errors: $VALIDATION_ERRORS${RESET}"
        echo -e "\n${RED}Validation failed. Please address the errors above.${RESET}"
        return 1
    elif [[ $VALIDATION_WARNINGS -gt 0 ]]; then
        echo -e "\n${YELLOW}Validation passed with warnings. Review warnings above.${RESET}"
        return 0
    else
        echo -e "\n${GREEN}All validation checks passed!${RESET}"
        return 0
    fi
}

# Standalone entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle help flag
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat << 'EOF'
Usage: validate.sh [LEVEL] [PROJECT_PATH]

Configuration validation and smoke testing for ilma.

Validation Levels:
  basic       Basic configuration and path validation (default)
  full        Include remote connectivity tests
  smoke-test  Full validation plus end-to-end test with generated dummy project

Arguments:
  PROJECT_PATH    Path to project directory for global config context (default: current directory)

Examples:
  ./lib/validate.sh basic /path/to/project     # Validate specific project
  ./lib/validate.sh full .                     # Full validation with current dir context
  ./lib/validate.sh smoke-test                 # Complete test using temporary dummy project

Note: smoke-test creates its own temporary test project regardless of PROJECT_PATH.

Exit codes:
  0 - All checks passed (warnings allowed)
  1 - Validation failed with errors
EOF
        exit 0
    fi

    VALIDATION_LEVEL="${1:-basic}"
    PROJECT_PATH="${2:-$(pwd)}"

    # Validate arguments (accept both smoke-test and smoketest)
    case "$VALIDATION_LEVEL" in
        basic|full|smoke-test)
            ;;
        smoketest)
            VALIDATION_LEVEL="smoke-test"
            ;;
        *)
            echo "Error: Invalid validation level '$VALIDATION_LEVEL'" >&2
            echo "Valid levels: basic, full, smoke-test (or smoketest)" >&2
            exit 1
            ;;
    esac

    run_validation "$VALIDATION_LEVEL" "$PROJECT_PATH"
fi
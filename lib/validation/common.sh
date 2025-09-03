#!/bin/bash
# lib/validation/common.sh - Shared validation utilities

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

validate_pass() {
    local message="$1"
    echo -e "${GREEN}✓${RESET} $message"
}

validate_fail() {
    local title="$1"
    local message="$2"
    echo -e "${RED}✗${RESET} $title"
    [[ -n "$message" ]] && echo "  ${RED}Error:${RESET} $message"
}

validate_warn() {
    local title="$1"
    local message="$2"
    echo -e "${YELLOW}!${RESET} $title"
    [[ -n "$message" ]] && echo "  ${YELLOW}Warning:${RESET} $message"
}

validate_info() {
    local message="$1"
    echo -e "${BLUE}i${RESET} $message"
}

section_header() {
    local title="$1"
    echo -e "\n${BLUE}=== $title ===${RESET}"
}
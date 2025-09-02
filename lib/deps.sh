#!/bin/bash
# lib/deps.sh - Dependency checker and analyzer for ilma

# Source required functions
ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Dependency tracking
declare -A REQUIRED_COMMANDS=()
declare -A OPTIONAL_COMMANDS=()
declare -A COMMAND_PURPOSE=()
declare -A MISSING_REQUIRED=()
declare -A MISSING_OPTIONAL=()

# Scan codebase for command dependencies
scan_dependencies() {
    echo -e "${BLUE}Scanning codebase for dependencies...${RESET}"

    # Core commands found in codebase
    local files_to_scan=("ilma" "lib/"*.sh "configs/"*.conf)

    for pattern in "${files_to_scan[@]}"; do
        if [[ "$pattern" == *"*"* ]]; then
            # Handle glob patterns
            for file in $pattern; do
                [[ -f "$file" ]] && scan_file "$file"
            done
        else
            [[ -f "$pattern" ]] && scan_file "$pattern"
        fi
    done

    # Add dependencies found through analysis
    add_known_dependencies
}

scan_file() {
    local file="$1"

    # Skip if file doesn't exist or is binary
    [[ ! -f "$file" || $(file "$file") == *"binary"* ]] && return

    # Scan for command -v checks (these are typically required)
    while IFS= read -r line; do
        if [[ "$line" =~ command[[:space:]]*-v[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
            local cmd="${BASH_REMATCH[1]}"
            # Only add if it's a real command we care about
            case "$cmd" in
                zstd|gzip|bzip2|xz|tar|rsync|ssh|gpg|tree|pv)
                    REQUIRED_COMMANDS["$cmd"]=1
                    ;;
            esac
        fi
    done < "$file"

    # Scan for direct command usage
    while IFS= read -r line; do
        # Look for common command patterns
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
            local cmd="${BASH_REMATCH[1]}"
            case "$cmd" in
                rsync)
                    REQUIRED_COMMANDS["rsync"]=1
                    add_command_purpose "rsync" "Remote file synchronization"
                    ;;
                ssh)
                    REQUIRED_COMMANDS["ssh"]=1
                    add_command_purpose "ssh" "Remote connectivity and operations"
                    ;;
                gpg)
                    OPTIONAL_COMMANDS["gpg"]=1
                    add_command_purpose "gpg" "File encryption/decryption (optional)"
                    ;;
                tar)
                    REQUIRED_COMMANDS["tar"]=1
                    add_command_purpose "tar" "Archive creation and extraction"
                    ;;
                find)
                    REQUIRED_COMMANDS["find"]=1
                    add_command_purpose "find" "File system traversal"
                    ;;
                tree)
                    OPTIONAL_COMMANDS["tree"]=1
                    add_command_purpose "tree" "Directory structure visualization (optional)"
                    ;;
            esac
        fi

        # Scan for compression command usage
        if [[ "$line" =~ (zstd|gzip|bzip2|xz)[[:space:]] ]]; then
            local comp_cmd="${BASH_REMATCH[1]}"
            OPTIONAL_COMMANDS["$comp_cmd"]=1
            add_command_purpose "$comp_cmd" "Compression algorithm (one required: zstd, gzip, bzip2, or xz)"
        fi

    done < "$file"
}

add_known_dependencies() {
    # Based on actual codebase analysis, add dependencies we know exist

    # Core tools that matter for installation
    REQUIRED_COMMANDS["bash"]=1
    REQUIRED_COMMANDS["tar"]=1
    REQUIRED_COMMANDS["find"]=1
    REQUIRED_COMMANDS["realpath"]=1
    REQUIRED_COMMANDS["readlink"]=1
    REQUIRED_COMMANDS["rsync"]=1
    REQUIRED_COMMANDS["ssh"]=1

    # Core purposes
    add_command_purpose "bash" "Shell interpreter (version 4.0+ for associative arrays)"
    add_command_purpose "tar" "Archive creation and extraction"
    add_command_purpose "find" "File system traversal and project analysis"
    add_command_purpose "realpath" "Path resolution (coreutils)"
    add_command_purpose "readlink" "Symbolic link resolution (coreutils)"

    # Compression tools (at least one required)
    OPTIONAL_COMMANDS["zstd"]=1
    OPTIONAL_COMMANDS["gzip"]=1
    OPTIONAL_COMMANDS["bzip2"]=1
    OPTIONAL_COMMANDS["xz"]=1

    # Remote sync tools
    REQUIRED_COMMANDS["rsync"]=1
    REQUIRED_COMMANDS["ssh"]=1

    # Optional tools
    OPTIONAL_COMMANDS["gpg"]=1
    OPTIONAL_COMMANDS["tree"]=1
    OPTIONAL_COMMANDS["pv"]=1

    add_command_purpose "rsync" "Remote file synchronization and backup operations"
    add_command_purpose "ssh" "Remote server connectivity and operations"
    add_command_purpose "gpg" "File encryption and decryption (optional)"
    add_command_purpose "tree" "Directory structure visualization in output (optional)"
    add_command_purpose "pv" "Progress visualization for large operations (future feature)"
    add_command_purpose "zstd" "Fast compression algorithm (recommended)"
    add_command_purpose "gzip" "Standard compression algorithm (widely available)"
    add_command_purpose "bzip2" "High compression ratio algorithm"
    add_command_purpose "xz" "High compression ratio algorithm"
}

add_command_purpose() {
    local cmd="$1"
    local purpose="$2"
    COMMAND_PURPOSE["$cmd"]="$purpose"
}

check_dependencies() {
    echo -e "\n${BLUE}Checking dependencies...${RESET}"

    local required_missing=0
    local optional_missing=0

    # Check required dependencies
    echo -e "\n${BLUE}=== Required Dependencies ===${RESET}"
    for cmd in "${!REQUIRED_COMMANDS[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            local version=""
            case "$cmd" in
                bash)
                    version=" ($(bash --version | head -1 | awk '{print $4}' | cut -d'(' -f1))"
                    ;;
                rsync)
                    version=" ($(rsync --version | head -1 | awk '{print $3}'))"
                    ;;
                tar)
                    version=" ($(tar --version | head -1 | awk '{print $4}' 2>/dev/null || echo "unknown"))"
                    ;;
            esac
            echo -e "${GREEN}✓${RESET} $cmd$version - ${COMMAND_PURPOSE[$cmd]}"
        else
            echo -e "${RED}✗${RESET} $cmd - ${COMMAND_PURPOSE[$cmd]}"
            MISSING_REQUIRED["$cmd"]=1
            ((required_missing++))
        fi
    done

    # Check optional dependencies
    echo -e "\n${BLUE}=== Optional Dependencies ===${RESET}"
    for cmd in "${!OPTIONAL_COMMANDS[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            local version=""
            case "$cmd" in
                gpg)
                    version=" ($(gpg --version | head -1 | awk '{print $3}'))"
                    ;;
                zstd)
                    version=" ($(zstd --version | awk '{print $2}' | head -1))"
                    ;;
                gzip)
                    version=" ($(gzip --version | head -1 | awk '{print $2}'))"
                    ;;
            esac
            echo -e "${GREEN}✓${RESET} $cmd$version - ${COMMAND_PURPOSE[$cmd]}"
        else
            echo -e "${YELLOW}!${RESET} $cmd - ${COMMAND_PURPOSE[$cmd]}"
            MISSING_OPTIONAL["$cmd"]=1
            ((optional_missing++))
        fi
    done

    # Check compression availability
    echo -e "\n${BLUE}=== Compression Algorithm Check ===${RESET}"
    local compression_available=false
    for comp in zstd gzip bzip2 xz; do
        if command -v "$comp" &>/dev/null; then
            compression_available=true
            break
        fi
    done

    if [[ "$compression_available" == true ]]; then
        echo -e "${GREEN}✓${RESET} At least one compression algorithm is available"
    else
        echo -e "${RED}✗${RESET} No compression algorithms found (install at least one: zstd, gzip, bzip2, or xz)"
        ((required_missing++))
    fi

    return $required_missing
}

show_installation_help() {
    if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]] || [[ ${#MISSING_OPTIONAL[@]} -gt 0 ]]; then
        echo -e "\n${BLUE}=== Installation Help ===${RESET}"

        # Required packages
        if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
            echo -e "\n${RED}Missing required packages:${RESET}"
            for cmd in "${!MISSING_REQUIRED[@]}"; do
                echo "  $cmd - ${COMMAND_PURPOSE[$cmd]}"
            done

            echo -e "\n${BLUE}Installation commands by system:${RESET}"

            # Fedora/RHEL
            echo -e "${YELLOW}Fedora/RHEL/CentOS:${RESET}"
            local fedora_packages=""
            for cmd in "${!MISSING_REQUIRED[@]}"; do
                case "$cmd" in
                    rsync) fedora_packages+=" rsync" ;;
                    realpath|readlink) fedora_packages+=" coreutils" ;;
                    tar) fedora_packages+=" tar" ;;
                    find) fedora_packages+=" findutils" ;;
                    ssh) fedora_packages+=" openssh-clients" ;;
                esac
            done
            [[ -n "$fedora_packages" ]] && echo "  sudo dnf install$fedora_packages"

            # Debian/Ubuntu
            echo -e "${YELLOW}Debian/Ubuntu:${RESET}"
            local debian_packages=""
            for cmd in "${!MISSING_REQUIRED[@]}"; do
                case "$cmd" in
                    rsync) debian_packages+=" rsync" ;;
                    realpath|readlink) debian_packages+=" coreutils" ;;
                    tar) debian_packages+=" tar" ;;
                    find) debian_packages+=" findutils" ;;
                    ssh) debian_packages+=" openssh-client" ;;
                esac
            done
            [[ -n "$debian_packages" ]] && echo "  sudo apt install$debian_packages"

            # macOS
            echo -e "${YELLOW}macOS:${RESET}"
            for cmd in "${!MISSING_REQUIRED[@]}"; do
                case "$cmd" in
                    rsync) echo "  brew install rsync" ;;
                    realpath) echo "  brew install coreutils" ;;
                esac
            done
        fi

        # Optional packages
        if [[ ${#MISSING_OPTIONAL[@]} -gt 0 ]]; then
            echo -e "\n${YELLOW}Missing optional packages (for enhanced functionality):${RESET}"
            for cmd in "${!MISSING_OPTIONAL[@]}"; do
                echo "  $cmd - ${COMMAND_PURPOSE[$cmd]}"
            done

            echo -e "\n${BLUE}Optional package installation:${RESET}"
            echo -e "${YELLOW}Fedora/RHEL:${RESET} sudo dnf install zstd gpg tree pv"
            echo -e "${YELLOW}Debian/Ubuntu:${RESET} sudo apt install zstd gnupg tree pv"
            echo -e "${YELLOW}macOS:${RESET} brew install zstd gnupg tree pv"
        fi
    fi
}

generate_dependency_report() {
    echo -e "\n${BLUE}=== Dependency Summary for README ===${RESET}"

    echo -e "\n${BLUE}Required System Dependencies:${RESET}"
    echo "- bash (4.0+) - Shell interpreter with associative array support"
    echo "- tar - Archive creation and extraction"
    echo "- rsync - File synchronization and backup operations"
    echo "- ssh - Remote server connectivity"
    echo "- find, grep, sed, awk - File system traversal and text processing"
    echo "- coreutils (realpath, readlink, etc.) - Core POSIX utilities"
    echo "- At least one compression tool: zstd (recommended), gzip, bzip2, or xz"

    echo -e "\n${BLUE}Optional Dependencies:${RESET}"
    echo "- gpg - File encryption/decryption capabilities"
    echo "- tree - Enhanced directory structure visualization"
    echo "- pv - Progress bars for large operations (future feature)"

    echo -e "\n${BLUE}Compression Algorithm Support:${RESET}"
    echo "- zstd (recommended) - Fast compression with good ratios"
    echo "- gzip - Widely available, moderate compression"
    echo "- bzip2 - Higher compression ratios, slower"
    echo "- xz - High compression ratios"
}

# Main dependency check function
run_dependency_check() {
    local mode="${1:-check}"

    case "$mode" in
        scan)
            scan_dependencies
            ;;
        check)
            scan_dependencies
            if check_dependencies; then
                echo -e "\n${GREEN}All required dependencies satisfied!${RESET}"
            else
                echo -e "\n${RED}Missing required dependencies detected.${RESET}"
                show_installation_help
                return 1
            fi
            ;;
        report)
            scan_dependencies
            check_dependencies
            generate_dependency_report
            ;;
        install-help)
            scan_dependencies
            check_dependencies &>/dev/null
            show_installation_help
            ;;
        *)
            echo "Usage: deps.sh [scan|check|report|install-help]"
            return 1
            ;;
    esac
}

# Standalone entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle help flag
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat << 'EOF'
Usage: deps.sh [MODE]

Dependency checker and analyzer for ilma.

Modes:
  check        Check all dependencies and show status (default)
  scan         Scan codebase for dependencies only
  report       Generate dependency summary for documentation
  install-help Show installation commands for missing dependencies

Examples:
  ./lib/deps.sh                    # Check all dependencies
  ./lib/deps.sh report             # Generate README-ready dependency list
  ./lib/deps.sh install-help       # Show how to install missing dependencies

Exit codes:
  0 - All required dependencies available
  1 - Missing required dependencies
EOF
        exit 0
    fi

    run_dependency_check "${1:-check}"
fi

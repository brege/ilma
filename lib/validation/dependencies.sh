#!/bin/bash
# lib/validation/dependencies.sh - System dependency validation

# Required tools
required_tools=(
    "rsync:Remote file synchronization and backup operations"
    "find:File system traversal and project analysis"
    "bash:Shell interpreter (version 4.0+ for associative arrays)"
    "realpath:Path resolution (coreutils)"
    "readlink:Symbolic link resolution (coreutils)"
    "ssh:Remote server connectivity and operations"
    "tar:Archive creation and extraction"
)

# Optional tools
optional_tools=(
    "gpg:File encryption and decryption (optional)"
    "tree:Directory structure visualization in output (optional)"
    "xz:High compression ratio algorithm"
    "pv:Progress visualization for large operations (future feature)"
    "zstd:Fast compression algorithm (recommended)"
    "gzip:Standard compression algorithm (widely available)"
    "bzip2:High compression ratio algorithm"
)

echo "SECTION:Required Dependencies"

all_required=true
for tool_desc in "${required_tools[@]}"; do
    tool="${tool_desc%%:*}"
    desc="${tool_desc#*:}"
    if command -v "$tool" >/dev/null 2>&1; then
        version=""
        case "$tool" in
            rsync) version=$(rsync --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+') ;;
            bash) version=$BASH_VERSION ;;
            tar) version=$(tar --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+') ;;
        esac
        if [[ -n "$version" ]]; then
            echo "PASS:$tool ($version) - $desc"
        else
            echo "PASS:$tool - $desc"
        fi
    else
        echo "FAIL:$tool:$desc"
        all_required=false
    fi
done

echo "SECTION:Optional Dependencies"

for tool_desc in "${optional_tools[@]}"; do
    tool="${tool_desc%%:*}"
    desc="${tool_desc#*:}"
    if command -v "$tool" >/dev/null 2>&1; then
        version=""
        case "$tool" in
            gpg) version=$(gpg --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+') ;;
            gzip) version=$(gzip --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+') ;;
            zstd) version="(Zstandard)" ;;
        esac
        if [[ -n "$version" ]]; then
            echo "PASS:$tool $version - $desc"
        else
            echo "PASS:$tool - $desc"
        fi
    else
        echo "INFO:$tool - $desc (not installed)"
    fi
done

echo "SECTION:Compression Algorithm Check"
if command -v zstd >/dev/null 2>&1 || command -v gzip >/dev/null 2>&1 || command -v bzip2 >/dev/null 2>&1 || command -v xz >/dev/null 2>&1; then
    echo "PASS:At least one compression algorithm is available"
else
    echo "FAIL:Compression algorithms:No compression tools found"
    all_required=false
fi

if [[ "$all_required" == true ]]; then
    echo "SUMMARY:PASS:All required dependencies satisfied"
else
    echo "SUMMARY:FAIL:Some required dependencies are missing"
fi
#!/bin/bash
# lib/validation/compression.sh - Compression system validation

echo "SECTION:Compression Support"

compression_type="${COMPRESSION_TYPE:-zstd}"

case "$compression_type" in
    zstd)
        if command -v zstd >/dev/null 2>&1; then
            echo "PASS:Compression algorithm (zstd)"
        else
            echo "FAIL:Compression algorithm:zstd not found (configured type)"
        fi
        ;;
    gzip)
        if command -v gzip >/dev/null 2>&1; then
            echo "PASS:Compression algorithm (gzip)"
        else
            echo "FAIL:Compression algorithm:gzip not found (configured type)"
        fi
        ;;
    bzip2)
        if command -v bzip2 >/dev/null 2>&1; then
            echo "PASS:Compression algorithm (bzip2)"
        else
            echo "FAIL:Compression algorithm:bzip2 not found (configured type)"
        fi
        ;;
    xz)
        if command -v xz >/dev/null 2>&1; then
            echo "PASS:Compression algorithm (xz)"
        else
            echo "FAIL:Compression algorithm:xz not found (configured type)"
        fi
        ;;
    *)
        echo "FAIL:Compression algorithm:Unknown type: $compression_type"
        ;;
esac

if command -v tar >/dev/null 2>&1; then
    echo "PASS:Archive tool (tar)"
else
    echo "FAIL:Archive tool:tar command not found"
fi
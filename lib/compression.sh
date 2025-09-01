#!/bin/bash
# lib/compression.sh - Compression utilities for archives

get_compression_cmd() {
    local comp_type="$1"
    local comp_level="$2"

    case "$comp_type" in
        zstd)
            echo "zstd -${comp_level}"
            ;;
        gzip)
            echo "gzip -${comp_level}"
            ;;
        bzip2)
            echo "bzip2 -${comp_level}"
            ;;
        xz)
            echo "xz -${comp_level}"
            ;;
        lzma)
            echo "lzma -${comp_level}"
            ;;
        none)
            echo "cat"
            ;;
        *)
            echo "Unknown compression type: $comp_type" >&2
            exit 1
            ;;
    esac
}

get_archive_extension() {
    local comp_type="$1"

    case "$comp_type" in
        zstd) echo ".tar.zst" ;;
        gzip) echo ".tar.gz" ;;
        bzip2) echo ".tar.bz2" ;;
        xz) echo ".tar.xz" ;;
        lzma) echo ".tar.lzma" ;;
        none) echo ".tar" ;;
        *) echo ".tar" ;;
    esac
}

get_tar_option() {
    local comp_type="$1"

    case "$comp_type" in
        zstd) echo "-I zstd" ;;
        gzip) echo "-z" ;;
        bzip2) echo "-j" ;;
        xz) echo "-J" ;;
        lzma) echo "--lzma" ;;
        none) echo "" ;;
        *) echo "" ;;
    esac
}

is_archive() {
    local file="$1"
    [[ "$file" =~ \.(tar|tar\.gz|tar\.bz2|tar\.xz|tar\.zst|tar\.lzma|tgz|tbz2|txz)$ ]]
}

is_compressed_archive() {
    local file="$1"
    [[ "$file" =~ \.(tar\.gz|tar\.bz2|tar\.xz|tar\.zst|tar\.lzma|tgz|tbz2|txz)$ ]]
}

get_compression_type_from_file() {
    local file="$1"

    case "$file" in
        *.tar.zst) echo "zstd" ;;
        *.tar.gz|*.tgz) echo "gzip" ;;
        *.tar.bz2|*.tbz2) echo "bzip2" ;;
        *.tar.xz|*.txz) echo "xz" ;;
        *.tar.lzma) echo "lzma" ;;
        *.tar) echo "none" ;;
        *) echo "none" ;;
    esac
}
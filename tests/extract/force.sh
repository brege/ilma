#!/bin/bash
set -uo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
helpers_path="$(cd "$script_directory/.." && pwd)/helpers/assert.sh"
source "$helpers_path"

repository_root="$(cd "$script_directory/../.." && pwd)"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

archive_dir="$temporary_root/archive"
mkdir -p "$archive_dir"
echo "data" > "$archive_dir/file.txt"
tar -czf "$temporary_root/test.tar.gz" -C "$archive_dir" .

target_dir="$temporary_root/output"
mkdir -p "$target_dir"

run_command --workdir "$repository_root" "$repository_root/commands/decrypt.sh" --force --target "$target_dir" "$temporary_root/test.tar.gz"
assert_exit 0
assert_file_exists "$target_dir"

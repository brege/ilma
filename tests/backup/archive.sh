#!/bin/bash
set -uo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
helpers_path="$(cd "$script_directory/.." && pwd)/helpers/assert.sh"
source "$helpers_path"

repository_root="$(cd "$script_directory/../.." && pwd)"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

run_command --workdir "$repository_root" "$repository_root/tools/make-dummies.sh" "$temporary_root"
assert_exit 0

project_path="$temporary_root/dummy-project-python"
run_command --workdir "$repository_root" "$repository_root/ilma" --archive "$project_path" --type python
assert_exit 0

archive_path="$(find "$temporary_root" -maxdepth 1 -type f -name 'dummy-project-python*.tar*' | head -n 1)"
assert_not_empty "$archive_path"
assert_file_exists "$archive_path"

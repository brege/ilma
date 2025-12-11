#!/bin/bash
set -uo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
helpers_path="$(cd "$script_directory/.." && pwd)/helpers/assert.sh"
source "$helpers_path"

repository_root="$(cd "$script_directory/../.." && pwd)"

run_command --workdir "$repository_root" "$repository_root/ilma" decrypt --help
assert_exit 0
assert_contains "$COMMAND_STDOUT" "Usage: ilma decrypt"
assert_contains "$COMMAND_STDOUT" "Decrypt a GPG-encrypted file"

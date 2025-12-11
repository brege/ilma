#!/bin/bash
set -uo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
export PATH="$repository_root:$PATH"

status=0

while IFS= read -r -d '' test_file; do
    test_name="${test_file#"$repository_root"/}"
    printf "Running %s... " "$test_name"
    if bash "$test_file"; then
        printf "ok\n"
    else
        printf "FAIL\n"
        status=1
    fi
done < <(find "$repository_root/tests" -type f -name "*.sh" ! -path "*/helpers/*" ! -name "run.sh" -print0 | sort -z)

exit "$status"

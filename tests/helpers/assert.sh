#!/bin/bash
set -uo pipefail

COMMAND_STDOUT=""
COMMAND_STDERR=""
COMMAND_STATUS=0

fail() {
    printf "%s\n" "$1"
    exit 1
}

run_command() {
    local working_directory="$PWD"
    if [[ "${1:-}" == "--workdir" ]]; then
        working_directory="$2"
        shift 2
    fi

    local stdout_file
    local stderr_file
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    (
        cd "$working_directory" || exit
        "$@"
    ) >"$stdout_file" 2>"$stderr_file"
    COMMAND_STATUS=$?
    COMMAND_STDOUT="$(cat "$stdout_file")"
    COMMAND_STDERR="$(cat "$stderr_file")"
    rm -f "$stdout_file" "$stderr_file"
}

assert_exit() {
    local expected_status="$1"
    if [[ "$COMMAND_STATUS" -ne "$expected_status" ]]; then
        fail "Expected exit $expected_status but got $COMMAND_STATUS"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if ! grep -Fq "$needle" <<<"$haystack"; then
        fail "Expected to find \"$needle\" in output"
    fi
}

assert_not_empty() {
    local value="$1"
    if [[ -z "$value" ]]; then
        fail "Expected value to be non-empty"
    fi
}

assert_file_exists() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        fail "Expected file or directory at $path"
    fi
}

assert_file_absent() {
    local path="$1"
    if [[ -e "$path" ]]; then
        fail "Expected $path to be absent"
    fi
}

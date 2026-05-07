#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/test.sh"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"${TMP_DIR}/.env" <<'ENV'
TEST_STREAMING_VALUE=from-dotenv
QUOTED_VALUE="with spaces"
ENV

stream_output="$(
    cd "$TMP_DIR"
    bash -s -- --color green --show-env alpha "two words" < "$SCRIPT"
)"

assert_contains "$stream_output" "Streaming worked!"
assert_contains "$stream_output" "Arguments (2):"
assert_contains "$stream_output" "1: alpha"
assert_contains "$stream_output" "2: two words"
assert_contains "$stream_output" ".env contents:"
assert_contains "$stream_output" "TEST_STREAMING_VALUE=from-dotenv"
assert_contains "$stream_output" "QUOTED_VALUE=\"with spaces\""
assert_contains "$stream_output" $'\033[1;32m'

prompt_output="$(
    cd "$TMP_DIR"
    printf 'Ada\n' | script -qfec "bash '$SCRIPT' --no-color --prompt" /dev/null
)"

assert_contains "$prompt_output" "You entered: Ada"

printf 'ok - test.sh streaming behaviors\n'

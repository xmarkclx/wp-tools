#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

TMP_DIR="$(mktemp -d)"
BIN_DIR="${TMP_DIR}/bin"
PROJECT_DIR="${TMP_DIR}/project"
mkdir -p "$BIN_DIR" "$PROJECT_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "${ROOT_DIR}/wp-prepare-sync-env" "${BIN_DIR}/wp-prepare-sync-env"
cp "${ROOT_DIR}/wp-tools-lib.sh" "${BIN_DIR}/wp-tools-lib.sh"
chmod +x "${BIN_DIR}/wp-prepare-sync-env"

# 🧪 Creates sync.env when absent
out="$(
    cd "$PROJECT_DIR"
    PATH="${BIN_DIR}:$PATH" WP_TOOLS_DIR="$PROJECT_DIR" wp-prepare-sync-env 2>&1
)"
assert_contains "$out" "Created"
assert_contains "$out" "sync.env"
[[ -f "${PROJECT_DIR}/sync.env" ]] || fail "sync.env should exist"

grep -q '^SSH_HOST=user@example.com$' "${PROJECT_DIR}/sync.env" \
    || fail "expected dummy SSH_HOST line"
grep -q '^WP_DIR=/var/www/example.com/httpdocs$' "${PROJECT_DIR}/sync.env" \
    || fail "expected dummy WP_DIR line"

# 🧪 Second run does not overwrite
echo "SHOULD_NOT_REPLACE=1" >>"${PROJECT_DIR}/sync.env"
out2="$(
    cd "$PROJECT_DIR"
    PATH="${BIN_DIR}:$PATH" WP_TOOLS_DIR="$PROJECT_DIR" wp-prepare-sync-env 2>&1
)"
assert_contains "$out2" "already exists"
grep -q 'SHOULD_NOT_REPLACE=1' "${PROJECT_DIR}/sync.env" \
    || fail "sync.env should be unchanged on second run"

printf 'ok - wp-prepare-sync-env\n'

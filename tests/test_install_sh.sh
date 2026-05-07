#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/install.sh"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_file() {
    local path="$1"
    [[ -f "$path" ]] || fail "expected file to exist: $path"
}

assert_executable() {
    local path="$1"
    [[ -x "$path" ]] || fail "expected file to be executable: $path"
}

assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

output="$(
    HOME="$TMP_HOME" SHELL="/bin/zsh" bash "$SCRIPT" 2>&1
)"

assert_contains "$output" "📦 Installing wp-tools commands"
assert_contains "$output" "✅ Installed wp-sync-all"
assert_contains "$output" "✅ Installed wp-tools-lib.sh"
assert_contains "$output" "🎉 Install complete"

for command in wp-sync-all wp-sync-db wp-sync-files wp-sync-uploads wp-restore-db wp-tools-lib.sh; do
    assert_file "${TMP_HOME}/bin/${command}"
done

for command in wp-sync-all wp-sync-db wp-sync-files wp-sync-uploads wp-restore-db; do
    assert_executable "${TMP_HOME}/bin/${command}"
done

profile_contents="$(cat "${TMP_HOME}/.zshrc")"
assert_contains "$profile_contents" 'export PATH="$HOME/bin:$PATH"'

second_output="$(
    HOME="$TMP_HOME" SHELL="/bin/zsh" bash "$SCRIPT" 2>&1
)"

assert_contains "$second_output" "✅ PATH already includes ~/bin in ${TMP_HOME}/.zshrc"

path_line_count="$(grep -Fc 'export PATH="$HOME/bin:$PATH"' "${TMP_HOME}/.zshrc")"
[[ "$path_line_count" == "1" ]] || fail "expected one PATH line, found ${path_line_count}"

STREAM_HOME="$(mktemp -d)"
REMOTE_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$STREAM_HOME" "$REMOTE_DIR"' EXIT

for command in wp-sync-all wp-sync-db wp-sync-files wp-sync-uploads wp-restore-db wp-tools-lib.sh; do
    cp "${ROOT_DIR}/${command}" "${REMOTE_DIR}/${command}"
done

stream_output="$(
    HOME="$STREAM_HOME" \
    SHELL="/bin/bash" \
    WP_TOOLS_INSTALL_BASE_URL="file://${REMOTE_DIR}" \
    bash -s < "$SCRIPT" 2>&1
)"

assert_contains "$stream_output" "📦 Installing wp-tools commands"
assert_contains "$stream_output" "✅ Installed wp-sync-files"
assert_contains "$stream_output" "🎉 Install complete"
assert_file "${STREAM_HOME}/bin/wp-sync-all"
assert_file "${STREAM_HOME}/bin/wp-tools-lib.sh"
assert_contains "$(cat "${STREAM_HOME}/.bashrc")" 'export PATH="$HOME/bin:$PATH"'

printf 'ok - install.sh installs wp-tools into ~/bin\n'

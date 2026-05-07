#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/sync-all.sh"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_exists() {
    local path="$1"
    [[ ! -e "$path" ]] || fail "expected path not to exist: $path"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"${TMP_DIR}/sync-db.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'sync-db:%s\n' "$*" >> sync-order.log
SH
chmod +x "${TMP_DIR}/sync-db.sh"

cat >"${TMP_DIR}/sync-uploads.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'sync-uploads:%s\n' "$*" >> sync-order.log
SH
chmod +x "${TMP_DIR}/sync-uploads.sh"

missing_output="$(
    cd "$TMP_DIR"
    set +e
    SYNC_DB_DIR="$TMP_DIR" bash "$SCRIPT" 2>&1
    printf 'exit:%s\n' "$?"
)"

assert_contains "$missing_output" "❌ Missing ${TMP_DIR}/src.env"
assert_contains "$missing_output" $'\033[1;31m[sync-all]\033[0m'
assert_contains "$missing_output" "exit:1"
assert_not_exists "${TMP_DIR}/sync-order.log"

cat >"${TMP_DIR}/src.env" <<'ENV'
SSH_HOST=deploy@example.com
WP_DIR=/var/www/example.com/httpdocs
ENV

cat >"${TMP_DIR}/.env" <<'ENV'
DB_NAME=wordpress
DB_USER=wp_user
DB_PASSWORD="secret with spaces"
ENV

valid_output="$(
    cd "$TMP_DIR"
    SYNC_DB_DIR="$TMP_DIR" bash "$SCRIPT" 2>&1
)"

assert_contains "$valid_output" "✅ src.env has SSH_HOST"
assert_contains "$valid_output" "✅ .env has DB_PASSWORD"
assert_contains "$valid_output" "🗄️  Running database sync"
assert_contains "$valid_output" "🖼️  Running uploads sync"
assert_contains "$valid_output" "🎉 Full sync complete"
assert_contains "$valid_output" $'\033[1;34m[sync-all]\033[0m'

expected_order=$'sync-db:\nsync-uploads:'
actual_order="$(cat "${TMP_DIR}/sync-order.log")"
[[ "$actual_order" == "$expected_order" ]] || fail "unexpected command order: $actual_order"

rm -f "${TMP_DIR}/sync-order.log"

stream_output="$(
    cd "$TMP_DIR"
    bash -s < "$SCRIPT" 2>&1
)"

assert_contains "$stream_output" "🎉 Full sync complete"

expected_stream_order=$'sync-db:\nsync-uploads:'
actual_stream_order="$(cat "${TMP_DIR}/sync-order.log")"
[[ "$actual_stream_order" == "$expected_stream_order" ]] || fail "unexpected streamed command order: $actual_stream_order"

rm -f "${TMP_DIR}/sync-order.log"

dry_run_output="$(
    cd "$TMP_DIR"
    SYNC_DB_DIR="$TMP_DIR" bash "$SCRIPT" --uploads-dry-run 2>&1
)"

assert_contains "$dry_run_output" "🧪 Uploads dry-run enabled"

expected_dry_run_order=$'sync-db:\nsync-uploads:--dry-run'
actual_dry_run_order="$(cat "${TMP_DIR}/sync-order.log")"
[[ "$actual_dry_run_order" == "$expected_dry_run_order" ]] || fail "unexpected dry-run command order: $actual_dry_run_order"

FALLBACK_DIR="$(mktemp -d)"
REMOTE_SCRIPT_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR" "$FALLBACK_DIR" "$REMOTE_SCRIPT_DIR"' EXIT

cat >"${FALLBACK_DIR}/src.env" <<'ENV'
SSH_HOST=deploy@example.com
WP_DIR=/var/www/example.com/httpdocs
ENV

cat >"${FALLBACK_DIR}/.env" <<'ENV'
DB_NAME=wordpress
DB_USER=wp_user
DB_PASSWORD=secret
ENV

cat >"${REMOTE_SCRIPT_DIR}/sync-db.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'remote-sync-db:%s\n' "$*" >> sync-order.log
SH

cat >"${REMOTE_SCRIPT_DIR}/sync-uploads.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'remote-sync-uploads:%s\n' "$*" >> sync-order.log
SH

fallback_output="$(
    cd "$FALLBACK_DIR"
    SYNC_ALL_SCRIPT_BASE_URL="file://${REMOTE_SCRIPT_DIR}" bash -s < "$SCRIPT" 2>&1
)"

assert_contains "$fallback_output" "🌐 Fetching sync-db.sh"
assert_contains "$fallback_output" "🌐 Fetching sync-uploads.sh"
assert_contains "$fallback_output" "🎉 Full sync complete"

expected_fallback_order=$'remote-sync-db:\nremote-sync-uploads:'
actual_fallback_order="$(cat "${FALLBACK_DIR}/sync-order.log")"
[[ "$actual_fallback_order" == "$expected_fallback_order" ]] || fail "unexpected fallback command order: $actual_fallback_order"

printf 'ok - sync-all.sh validates env and delegates in order\n'

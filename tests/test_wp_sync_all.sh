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

assert_not_exists() {
    local path="$1"
    [[ ! -e "$path" ]] || fail "expected path not to exist: $path"
}

TMP_DIR="$(mktemp -d)"
BIN_DIR="${TMP_DIR}/bin"
PROJECT_DIR="${TMP_DIR}/project"
mkdir -p "$BIN_DIR" "$PROJECT_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "${ROOT_DIR}/wp-sync-all" "${BIN_DIR}/wp-sync-all"
cp "${ROOT_DIR}/wp-tools-lib.sh" "${BIN_DIR}/wp-tools-lib.sh"
chmod +x "${BIN_DIR}/wp-sync-all"

cat >"${BIN_DIR}/wp-sync-db" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'wp-sync-db:%s\n' "$*" >> sync-order.log
SH
chmod +x "${BIN_DIR}/wp-sync-db"

cat >"${BIN_DIR}/wp-sync-files" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'wp-sync-files:%s\n' "$*" >> sync-order.log
SH
chmod +x "${BIN_DIR}/wp-sync-files"

missing_output="$(
    cd "$PROJECT_DIR"
    set +e
    PATH="${BIN_DIR}:$PATH" wp-sync-all 2>&1
    printf 'exit:%s\n' "$?"
)"

assert_contains "$missing_output" "❌ Missing ${PROJECT_DIR}/sync.env"
assert_contains "$missing_output" $'\033[1;31m[wp-sync-all]\033[0m'
assert_contains "$missing_output" "exit:1"
assert_not_exists "${PROJECT_DIR}/sync-order.log"

cat >"${PROJECT_DIR}/sync.env" <<'ENV'
SSH_HOST=deploy@example.com
WP_DIR=/var/www/example.com/httpdocs
ENV

cat >"${PROJECT_DIR}/.env" <<'ENV'
DB_NAME=wordpress
DB_USER=wp_user
DB_PASSWORD="secret with spaces"
ENV

valid_output="$(
    cd "$PROJECT_DIR"
    PATH="${BIN_DIR}:$PATH" wp-sync-all 2>&1
)"

assert_contains "$valid_output" "✅ sync.env has SSH_HOST"
assert_contains "$valid_output" "✅ .env has DB_PASSWORD"
assert_contains "$valid_output" "🗄️  Running database sync"
assert_contains "$valid_output" "📁 Running files sync"
assert_contains "$valid_output" "🎉 Full sync complete"
assert_contains "$valid_output" $'\033[1;34m[wp-sync-all]\033[0m'

expected_order=$'wp-sync-db:\nwp-sync-files:'
actual_order="$(cat "${PROJECT_DIR}/sync-order.log")"
[[ "$actual_order" == "$expected_order" ]] || fail "unexpected command order: $actual_order"

rm -f "${PROJECT_DIR}/sync-order.log"

dry_run_output="$(
    cd "$PROJECT_DIR"
    PATH="${BIN_DIR}:$PATH" wp-sync-all --files-dry-run 2>&1
)"

assert_contains "$dry_run_output" "🧪 Files dry-run enabled"

expected_dry_run_order=$'wp-sync-db:\nwp-sync-files:--dry-run'
actual_dry_run_order="$(cat "${PROJECT_DIR}/sync-order.log")"
[[ "$actual_dry_run_order" == "$expected_dry_run_order" ]] || fail "unexpected dry-run command order: $actual_dry_run_order"

rm -f "${PROJECT_DIR}/sync-order.log"

legacy_dry_run_output="$(
    cd "$PROJECT_DIR"
    PATH="${BIN_DIR}:$PATH" wp-sync-all --uploads-dry-run 2>&1
)"

assert_contains "$legacy_dry_run_output" "🧪 Files dry-run enabled"

expected_legacy_dry_run_order=$'wp-sync-db:\nwp-sync-files:--dry-run'
actual_legacy_dry_run_order="$(cat "${PROJECT_DIR}/sync-order.log")"
[[ "$actual_legacy_dry_run_order" == "$expected_legacy_dry_run_order" ]] || fail "unexpected legacy dry-run command order: $actual_legacy_dry_run_order"

printf 'ok - wp-sync-all validates env and delegates in order\n'

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

cp "${ROOT_DIR}/wp-sync-files" "${BIN_DIR}/wp-sync-files"
cp "${ROOT_DIR}/wp-tools-lib.sh" "${BIN_DIR}/wp-tools-lib.sh"
chmod +x "${BIN_DIR}/wp-sync-files"

cat >"${BIN_DIR}/rsync" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > rsync-args.log
SH
chmod +x "${BIN_DIR}/rsync"

missing_output="$(
    cd "$PROJECT_DIR"
    set +e
    PATH="${BIN_DIR}:$PATH" wp-sync-files 2>&1
    printf 'exit:%s\n' "$?"
)"

assert_contains "$missing_output" "❌ Missing ${PROJECT_DIR}/sync.env"
assert_contains "$missing_output" $'\033[1;31m[wp-sync-files]\033[0m'
assert_contains "$missing_output" "exit:1"

cat >"${PROJECT_DIR}/sync.env" <<'ENV'
SSH_HOST=deploy@example.com
WP_DIR=/var/www/example.com/httpdocs
SSH_PORT=2222
SRC_SYNC_DIR=web
DEST_SYNC_DIR=public
SYNC_EXCLUDE='node_modules/* cache/*'
ENV

valid_output="$(
    cd "$PROJECT_DIR"
    PATH="${BIN_DIR}:$PATH" wp-sync-files --dry-run 2>&1
)"

assert_contains "$valid_output" "🌐 Source: deploy@example.com:/var/www/example.com/httpdocs/web/"
assert_contains "$valid_output" "📂 Dest  : ${PROJECT_DIR}/public/"
assert_contains "$valid_output" "🧪 Dry-run mode"
assert_contains "$valid_output" "✅ Dry-run complete"

rsync_args="$(cat "${PROJECT_DIR}/rsync-args.log")"
assert_contains "$rsync_args" "--dry-run"
assert_contains "$rsync_args" "-e"
assert_contains "$rsync_args" "ssh -p 2222"
assert_contains "$rsync_args" "--exclude=.env"
assert_contains "$rsync_args" "--exclude=sync.env"
assert_contains "$rsync_args" "--exclude=backups/"
assert_contains "$rsync_args" "--exclude=node_modules/*"
assert_contains "$rsync_args" "--exclude=cache/*"
assert_contains "$rsync_args" "deploy@example.com:/var/www/example.com/httpdocs/web/"
assert_contains "$rsync_args" "${PROJECT_DIR}/public/"

printf 'ok - wp-sync-files builds full-folder rsync safely\n'

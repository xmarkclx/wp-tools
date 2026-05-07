#!/usr/bin/env bash
# 🔄 sync-all.sh — Validate WordPress sync config, then pull DB and uploads.
#
# 📥 Reads:
#   - ./src.env → SSH_HOST, WP_DIR
#   - ./.env    → DB_NAME, DB_USER, DB_PASSWORD
#
# 🚀 Usage:
#   ./sync-all.sh                         # sync database, then uploads
#   ./sync-all.sh --uploads-dry-run       # sync database, dry-run uploads
#
#   Streaming:
#   curl -fsSL https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-all.sh | bash

set -euo pipefail

SCRIPT_NAME="sync-all"
DEFAULT_SCRIPT_BASE_URL="https://raw.githubusercontent.com/xmarkclx/wp-tools/main"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
ok()   { printf '\033[1;32m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
err()  { printf '\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2; }

if [[ -n "${SYNC_DB_DIR:-}" ]]; then
    SCRIPT_DIR="$SYNC_DB_DIR"
elif [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$PWD"
fi
cd "$SCRIPT_DIR"

SRC_ENV_FILE="${SCRIPT_DIR}/src.env"
DEST_ENV_FILE="${SCRIPT_DIR}/.env"
SCRIPT_BASE_URL="${SYNC_ALL_SCRIPT_BASE_URL:-$DEFAULT_SCRIPT_BASE_URL}"
UPLOADS_DRY_RUN=0

while (( $# > 0 )); do
    case "$1" in
        --uploads-dry-run) UPLOADS_DRY_RUN=1; shift ;;
        -h|--help)         sed -n '1,16p' "$0"; exit 0 ;;
        *)                 err "❌ Unknown argument: $1"; exit 1 ;;
    esac
done

get_env_value() {
    local file="$1" key="$2" line value
    line="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n1 || true)"
    [[ -z "$line" ]] && return 1
    value="${line#*=}"
    value="${value%$'\r'}"
    if   [[ "$value" =~ ^\"(.*)\"$ ]]; then value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"
    fi
    printf '%s' "$value"
}

require_file() {
    local file="$1"
    [[ -f "$file" ]] || { err "❌ Missing $file"; exit 1; }
    ok "📄 Found ${file}"
}

require_env_key() {
    local file="$1" label="$2" key="$3"
    local value
    value="$(get_env_value "$file" "$key")" || { err "❌ ${key} missing in ${label}"; exit 1; }
    [[ -n "$value" ]] || { err "❌ ${key} is empty in ${label}"; exit 1; }
    ok "✅ ${label} has ${key}"
}

TMP_DIR=""
cleanup() {
    [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
    return 0
}
trap cleanup EXIT

resolve_script() {
    local name="$1"
    local local_path="${SCRIPT_DIR}/${name}"
    local remote_url="${SCRIPT_BASE_URL%/}/${name}"
    local downloaded_path

    if [[ -f "$local_path" ]]; then
        printf '%s' "$local_path"
        return 0
    fi

    command -v curl >/dev/null 2>&1 || { err "❌ ${name} not found locally and curl is unavailable"; exit 1; }
    [[ -n "$TMP_DIR" ]] || TMP_DIR="$(mktemp -d)"
    downloaded_path="${TMP_DIR}/${name}"

    log "🌐 Fetching ${name} from ${remote_url}" >&2
    curl -fsSL "$remote_url" -o "$downloaded_path" || { err "❌ Failed to fetch ${remote_url}"; exit 1; }
    chmod +x "$downloaded_path"
    printf '%s' "$downloaded_path"
}

log "🔎 Checking sync configuration"
require_file "$SRC_ENV_FILE"
require_file "$DEST_ENV_FILE"

require_env_key "$SRC_ENV_FILE" "src.env" SSH_HOST
require_env_key "$SRC_ENV_FILE" "src.env" WP_DIR
require_env_key "$DEST_ENV_FILE" ".env" DB_NAME
require_env_key "$DEST_ENV_FILE" ".env" DB_USER
require_env_key "$DEST_ENV_FILE" ".env" DB_PASSWORD

SYNC_DB_SCRIPT="$(resolve_script sync-db.sh)"
SYNC_UPLOADS_SCRIPT="$(resolve_script sync-uploads.sh)"

log "🗄️  Running database sync"
bash "$SYNC_DB_SCRIPT"
ok "✅ Database sync finished"

uploads_args=()
if [[ "$UPLOADS_DRY_RUN" -eq 1 ]]; then
    uploads_args+=(--dry-run)
    warn "🧪 Uploads dry-run enabled"
fi

log "🖼️  Running uploads sync"
bash "$SYNC_UPLOADS_SCRIPT" "${uploads_args[@]}"
ok "✅ Uploads sync finished"

ok "🎉 Full sync complete"

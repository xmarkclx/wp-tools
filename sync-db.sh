#!/usr/bin/env bash
# 🗄️  sync-db.sh — Pull the remote (source) WordPress database down to the
#                  local (destination) database, after taking a safety backup
#                  of the local DB first.
#
# 📥 Reads:
#   - ./src.env                     → SSH_HOST, WP_DIR (the remote WP root)
#   - ./.env                        → DB_NAME / DB_USER / DB_PASSWORD (local)
#   - <SSH_HOST>:<WP_DIR>/.env      → DB_NAME / DB_USER / DB_PASSWORD (remote)
#
# 📤 Writes:
#   - ./backups/db/<dbname>-YYYYmmdd-HHMMSS.sql.gz   (local safety backup)
#
# 🚀 Usage:
#   ./sync-db.sh           # interactive — asks for confirmation
#   ./sync-db.sh -y        # auto-yes, no prompt (for CI / cron)

set -euo pipefail

# 🎨 Pretty logging helpers
log()  { printf '\033[1;34m[sync-db]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[sync-db]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[sync-db]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[sync-db]\033[0m %s\n' "$*" >&2; }

# 📁 Always operate from the directory the script lives in
# 📁 Where to look for src.env / .env / backups/db.
#    - When run normally (`./sync-db.sh`) → directory that contains the script.
#    - When streamed (`bash <(curl …/sync-db.sh)` or `curl … | bash`) →
#      fall back to the current working directory, since BASH_SOURCE[0]
#      points at a /dev/fd/* pseudo-file in that case.
#    - Manual override: SYNC_DB_DIR=/some/path ./sync-db.sh
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
BACKUP_DIR="${SCRIPT_DIR}/backups/db"

# 🤖 CLI flags
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help)
            sed -n '1,25p' "$0"; exit 0 ;;
        *) err "Unknown argument: $arg"; exit 1 ;;
    esac
done

# -----------------------------------------------------------------------------
# 🔐 escape_mycnf_value <value>
#   Returns the value double-quoted and escaped so it's safe to drop into a
#   my.cnf-style [client] section. This is REQUIRED because MySQL's option-file
#   parser treats '#' as a comment marker mid-line — without quoting, a password
#   like "abc#123" silently becomes "abc" and auth fails.
#   Inside double quotes, MySQL recognises \" \\ \n \t \b \r \s \0, so we just
#   need to escape backslashes and double-quotes ourselves.
# -----------------------------------------------------------------------------
escape_mycnf_value() {
    local v="$1"
    v="${v//\\/\\\\}"   # escape backslashes first
    v="${v//\"/\\\"}"   # then escape double quotes
    printf '"%s"' "$v"
}

# -----------------------------------------------------------------------------
# 🔍 get_env_value <file> <KEY>
#   Extracts a value from an env-style file (KEY=value, KEY='value', KEY="value").
#   Strips matching surrounding quotes and trailing CR (Windows line endings).
# -----------------------------------------------------------------------------
get_env_value() {
    local file="$1" key="$2" line value
    # last matching line wins (mirrors typical dotenv behaviour)
    line="$(grep -E "^[[:space:]]*${key}=" "$file" | tail -n1 || true)"
    [[ -z "$line" ]] && return 1
    value="${line#*=}"
    value="${value%$'\r'}"
    if   [[ "$value" =~ ^\"(.*)\"$ ]]; then value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"
    fi
    printf '%s' "$value"
}

# 🧹 Tempfile cleanup on exit
TMP_FILES=()
cleanup() {
    local f
    for f in "${TMP_FILES[@]:-}"; do
        [[ -n "${f:-}" && -f "$f" ]] && rm -f "$f"
    done
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# 1️⃣  Read src.env (local file describing the remote)
# -----------------------------------------------------------------------------
[[ -f "$SRC_ENV_FILE"  ]] || { err "Missing $SRC_ENV_FILE";  exit 1; }
[[ -f "$DEST_ENV_FILE" ]] || { err "Missing $DEST_ENV_FILE"; exit 1; }

SSH_HOST="$(get_env_value "$SRC_ENV_FILE" SSH_HOST)" || { err "SSH_HOST missing in src.env"; exit 1; }
WP_DIR="$(get_env_value "$SRC_ENV_FILE" WP_DIR)"     || { err "WP_DIR missing in src.env";   exit 1; }
SSH_PORT="$(get_env_value "$SRC_ENV_FILE" SSH_PORT 2>/dev/null || true)"
SSH_PORT="${SSH_PORT:-22}"

log "🌐 Source: ${SSH_HOST}:${WP_DIR} (port ${SSH_PORT})"

# -----------------------------------------------------------------------------
# 2️⃣  Pull remote .env over SSH and parse credentials from it
# -----------------------------------------------------------------------------
log "🔑 Fetching remote .env via SSH …"
REMOTE_ENV_PATH="${WP_DIR%/}/.env"
REMOTE_ENV_CONTENT="$(ssh -p "$SSH_PORT" "$SSH_HOST" "cat ${REMOTE_ENV_PATH}")" \
    || { err "Failed to read ${REMOTE_ENV_PATH} on ${SSH_HOST}"; exit 1; }

REMOTE_ENV_TMP="$(mktemp)"
TMP_FILES+=("$REMOTE_ENV_TMP")
chmod 600 "$REMOTE_ENV_TMP"
printf '%s\n' "$REMOTE_ENV_CONTENT" > "$REMOTE_ENV_TMP"

SRC_DB_NAME="$(get_env_value "$REMOTE_ENV_TMP" DB_NAME)"         || { err "DB_NAME missing on remote";     exit 1; }
SRC_DB_USER="$(get_env_value "$REMOTE_ENV_TMP" DB_USER)"         || { err "DB_USER missing on remote";     exit 1; }
SRC_DB_PASSWORD="$(get_env_value "$REMOTE_ENV_TMP" DB_PASSWORD)" || { err "DB_PASSWORD missing on remote"; exit 1; }
SRC_DB_HOST="$(get_env_value "$REMOTE_ENV_TMP" DB_HOST 2>/dev/null || true)"
# 🔌 Default to 127.0.0.1 (TCP) instead of 'localhost' to avoid Unix-socket
#    auth quirks (mysqli 2002 / socket-path mismatches).
SRC_DB_HOST="${SRC_DB_HOST:-127.0.0.1}"

# -----------------------------------------------------------------------------
# 3️⃣  Read local .env (destination)
# -----------------------------------------------------------------------------
DEST_DB_NAME="$(get_env_value "$DEST_ENV_FILE" DB_NAME)"         || { err "DB_NAME missing in .env";     exit 1; }
DEST_DB_USER="$(get_env_value "$DEST_ENV_FILE" DB_USER)"         || { err "DB_USER missing in .env";     exit 1; }
DEST_DB_PASSWORD="$(get_env_value "$DEST_ENV_FILE" DB_PASSWORD)" || { err "DB_PASSWORD missing in .env"; exit 1; }
DEST_DB_HOST="$(get_env_value "$DEST_ENV_FILE" DB_HOST 2>/dev/null || true)"
# 🔌 Same as above — prefer TCP to avoid socket-auth issues.
DEST_DB_HOST="${DEST_DB_HOST:-127.0.0.1}"

log "📦 Source DB: ${SRC_DB_USER}@${SRC_DB_HOST}/${SRC_DB_NAME}"
log "📦 Dest   DB: ${DEST_DB_USER}@${DEST_DB_HOST}/${DEST_DB_NAME}"

# 🛑 Confirmation — about to overwrite the local DB
if [[ "$ASSUME_YES" -ne 1 ]]; then
    warn "This will OVERWRITE the local DB '${DEST_DB_NAME}' with data from '${SSH_HOST}:${SRC_DB_NAME}'."
    read -r -p "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { err "Aborted by user."; exit 1; }
fi

# -----------------------------------------------------------------------------
# 4️⃣  Build a defaults-extra-file for local mysql/mysqldump
#     (avoids leaking the password through the process list)
# -----------------------------------------------------------------------------
DEST_DEFAULTS_FILE="$(mktemp)"
TMP_FILES+=("$DEST_DEFAULTS_FILE")
chmod 600 "$DEST_DEFAULTS_FILE"
# 🔐 Values are quoted via escape_mycnf_value so that '#', spaces, etc. in the
#    password don't get misinterpreted by MySQL's option-file parser.
cat >"$DEST_DEFAULTS_FILE" <<EOF
[client]
user=$(escape_mycnf_value "$DEST_DB_USER")
password=$(escape_mycnf_value "$DEST_DB_PASSWORD")
host=$(escape_mycnf_value "$DEST_DB_HOST")
EOF

# 🩺 Sanity check: can we actually connect locally?
if ! mysql --defaults-extra-file="$DEST_DEFAULTS_FILE" -e "SELECT 1" "$DEST_DB_NAME" >/dev/null 2>&1; then
    err "Cannot connect to local DB '${DEST_DB_NAME}' as '${DEST_DB_USER}@${DEST_DB_HOST}'."
    exit 1
fi

# 📊 Detect `pv` (pipe viewer) so we can show live throughput / MB-per-second.
#    If pv isn't installed, we fall back to plain `cat` and just warn the user.
#    Flags used: -f (force output even if not a TTY), -b (bytes), -r (current rate),
#                -a (average rate), -t (elapsed time), -N (label).
if command -v pv >/dev/null 2>&1; then
    make_pv() { pv -f -b -r -a -t -N "$1"; }
else
    warn "'pv' is not installed — install it for a live throughput readout (e.g. \`apt install pv\` or \`brew install pv\`)."
    make_pv() { cat; }
fi

# -----------------------------------------------------------------------------
# 5️⃣  Backup the local DB → ./backups/db/<dbname>-<timestamp>.sql.gz
# -----------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/${DEST_DB_NAME}-${TIMESTAMP}.sql.gz"

log "💾 Backing up local DB → ${BACKUP_FILE}"
mysqldump --defaults-extra-file="$DEST_DEFAULTS_FILE" \
    --single-transaction --quick --routines --triggers --events \
    --default-character-set=utf8mb4 \
    --no-tablespaces \
    "$DEST_DB_NAME" \
    | make_pv "💾 backup (sql)" \
    | gzip -c > "$BACKUP_FILE"
ok "✅ Local backup saved ($(du -h "$BACKUP_FILE" | cut -f1))"

# -----------------------------------------------------------------------------
# 6️⃣  Stream `mysqldump` from the source over SSH straight into local mysql.
#     Credentials are passed via env vars so they never touch the process list,
#     and a temporary defaults file is written on the remote inside the heredoc.
# -----------------------------------------------------------------------------
log "⬇️  Dumping remote DB and importing into local …"
# 🔐 Pre-escape the source credentials for my.cnf format on the local side so
#    we don't have to ship the escape helper to the remote. The values arrive
#    on the remote already wrapped in double-quotes and ready to drop into the
#    [client] section verbatim.
SRC_DB_USER_MYCNF="$(escape_mycnf_value "$SRC_DB_USER")"
SRC_DB_PASS_MYCNF="$(escape_mycnf_value "$SRC_DB_PASSWORD")"
SRC_DB_HOST_MYCNF="$(escape_mycnf_value "$SRC_DB_HOST")"

# Pipeline:
#   ssh → mysqldump | gzip   (over the wire, compressed)
#       → gunzip              (decompress locally)
#       → pv                  (📊 live MB/s readout on stderr)
#       → mysql               (import into the destination DB)
ssh -p "$SSH_PORT" \
    -o "SendEnv=NONE" \
    "$SSH_HOST" \
    "DB_NAME=$(printf '%q' "$SRC_DB_NAME") \
     DB_USER_MYCNF=$(printf '%q' "$SRC_DB_USER_MYCNF") \
     DB_PASS_MYCNF=$(printf '%q' "$SRC_DB_PASS_MYCNF") \
     DB_HOST_MYCNF=$(printf '%q' "$SRC_DB_HOST_MYCNF") \
     bash -s" <<'REMOTE' \
    | gunzip -c \
    | make_pv "⬇️  import (sql)" \
    | mysql --defaults-extra-file="$DEST_DEFAULTS_FILE" "$DEST_DB_NAME"
set -euo pipefail
TMP="$(mktemp)"
chmod 600 "$TMP"
trap 'rm -f "$TMP"' EXIT
cat >"$TMP" <<EOF
[client]
user=$DB_USER_MYCNF
password=$DB_PASS_MYCNF
host=$DB_HOST_MYCNF
EOF
mysqldump --defaults-extra-file="$TMP" \
    --single-transaction --quick --routines --triggers --events \
    --default-character-set=utf8mb4 \
    --no-tablespaces \
    "$DB_NAME" | gzip -c
REMOTE

ok "🎉 Database sync complete: ${SSH_HOST}:${SRC_DB_NAME} → ${DEST_DB_NAME}"
log "🔁 Pre-sync backup of the previous local DB is at: ${BACKUP_FILE}"

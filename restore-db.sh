#!/usr/bin/env bash
# ♻️  restore-db.sh — Restore the local WordPress database from a backup
#                    produced by sync-db.sh (or any compatible .sql / .sql.gz dump).
#
# 📥 Reads:
#   - ./.env                                  → DB_NAME / DB_USER / DB_PASSWORD (local)
#   - ./backups/db/*.sql.gz | *.sql           → available backup files
#
# 📤 Writes:
#   - ./backups/db/<dbname>-pre-restore-YYYYmmdd-HHMMSS.sql.gz
#         (a safety snapshot of the *current* DB before restore — disable with --no-backup)
#
# 🚀 Usage:
#   ./restore-db.sh                                # interactive picker
#   ./restore-db.sh latest                         # newest backup in backups/db/
#   ./restore-db.sh backups/db/foo-2026...sql.gz   # specific file
#   ./restore-db.sh -y latest                      # skip the confirmation prompt
#   ./restore-db.sh --no-backup latest             # skip the pre-restore safety backup

set -euo pipefail

# 🎨 Pretty logging helpers
log()  { printf '\033[1;34m[restore-db]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[restore-db]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[restore-db]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[restore-db]\033[0m %s\n' "$*" >&2; }

# 📁 Where to look for .env / backups/db.
#    - When run normally (`./restore-db.sh`) → directory that contains the script.
#    - When streamed (`bash <(curl …/restore-db.sh)` or `curl … | bash`) →
#      fall back to the current working directory.
#    - Manual override: SYNC_DB_DIR=/some/path ./restore-db.sh
if [[ -n "${SYNC_DB_DIR:-}" ]]; then
    SCRIPT_DIR="$SYNC_DB_DIR"
elif [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$PWD"
fi
cd "$SCRIPT_DIR"

DEST_ENV_FILE="${SCRIPT_DIR}/.env"
BACKUP_DIR="${SCRIPT_DIR}/backups/db"

# 🤖 CLI flags
ASSUME_YES=0
DO_PRE_BACKUP=1
TARGET=""

while (( $# > 0 )); do
    case "$1" in
        -y|--yes)        ASSUME_YES=1; shift ;;
        --no-backup)     DO_PRE_BACKUP=0; shift ;;
        -h|--help)       sed -n '1,22p' "$0"; exit 0 ;;
        -*)              err "Unknown flag: $1"; exit 1 ;;
        *)               TARGET="$1"; shift ;;
    esac
done

# -----------------------------------------------------------------------------
# 🔐 escape_mycnf_value <value>
#   Double-quote-and-escape a value for a my.cnf [client] section so that
#   characters like '#' (option-file comment marker) don't truncate passwords.
# -----------------------------------------------------------------------------
escape_mycnf_value() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '"%s"' "$v"
}

# -----------------------------------------------------------------------------
# 🔍 get_env_value <file> <KEY>
# -----------------------------------------------------------------------------
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
# 1️⃣  Read local .env
# -----------------------------------------------------------------------------
[[ -f "$DEST_ENV_FILE" ]] || { err "Missing $DEST_ENV_FILE"; exit 1; }

DEST_DB_NAME="$(get_env_value "$DEST_ENV_FILE" DB_NAME)"         || { err "DB_NAME missing in .env";     exit 1; }
DEST_DB_USER="$(get_env_value "$DEST_ENV_FILE" DB_USER)"         || { err "DB_USER missing in .env";     exit 1; }
DEST_DB_PASSWORD="$(get_env_value "$DEST_ENV_FILE" DB_PASSWORD)" || { err "DB_PASSWORD missing in .env"; exit 1; }
DEST_DB_HOST="$(get_env_value "$DEST_ENV_FILE" DB_HOST 2>/dev/null || true)"
# 🔌 Default to 127.0.0.1 (TCP) — avoids the 'localhost' Unix-socket auth quirk.
DEST_DB_HOST="${DEST_DB_HOST:-127.0.0.1}"

# -----------------------------------------------------------------------------
# 2️⃣  Build a defaults-extra-file for local mysql/mysqldump (passwords-safe)
# -----------------------------------------------------------------------------
DEST_DEFAULTS_FILE="$(mktemp)"
TMP_FILES+=("$DEST_DEFAULTS_FILE")
chmod 600 "$DEST_DEFAULTS_FILE"
cat >"$DEST_DEFAULTS_FILE" <<EOF
[client]
user=$(escape_mycnf_value "$DEST_DB_USER")
password=$(escape_mycnf_value "$DEST_DB_PASSWORD")
host=$(escape_mycnf_value "$DEST_DB_HOST")
EOF

# 🩺 Sanity check: connectivity
if ! mysql --defaults-extra-file="$DEST_DEFAULTS_FILE" -e "SELECT 1" "$DEST_DB_NAME" >/dev/null 2>&1; then
    err "Cannot connect to local DB '${DEST_DB_NAME}' as '${DEST_DB_USER}@${DEST_DB_HOST}'."
    exit 1
fi

# -----------------------------------------------------------------------------
# 3️⃣  Resolve which backup file to restore.
#     - "latest" / no-arg with backups present → newest .sql.gz / .sql
#     - explicit path                          → use as-is
#     - no arg + interactive TTY               → numbered picker
# -----------------------------------------------------------------------------
list_backups() {
    # Print backups newest-first, one per line.
    [[ -d "$BACKUP_DIR" ]] || return 0
    # shellcheck disable=SC2012
    ls -1t "$BACKUP_DIR"/*.sql.gz "$BACKUP_DIR"/*.sql 2>/dev/null || true
}

resolve_target() {
    local choice="$1"

    # 📁 Explicit path provided
    if [[ -n "$choice" && "$choice" != "latest" ]]; then
        if [[ -f "$choice" ]]; then
            printf '%s' "$choice"; return 0
        fi
        # try relative to BACKUP_DIR
        if [[ -f "${BACKUP_DIR}/${choice}" ]]; then
            printf '%s' "${BACKUP_DIR}/${choice}"; return 0
        fi
        err "Backup file not found: $choice"; return 1
    fi

    # 🔝 "latest" or no arg → newest backup
    local newest
    newest="$(list_backups | head -n1)"
    if [[ -z "$newest" ]]; then
        err "No backups found in ${BACKUP_DIR}"
        return 1
    fi

    # If the user passed nothing AND we're on a TTY AND there's >1 backup,
    # show a numbered picker; otherwise just use the newest.
    if [[ -z "$choice" && -t 0 && -t 1 ]]; then
        local -a backups=()
        while IFS= read -r line; do backups+=("$line"); done < <(list_backups)

        if (( ${#backups[@]} > 1 )); then
            echo "📚 Available backups (newest first):" >&2
            local i=1
            for b in "${backups[@]}"; do
                local size mtime
                size="$(du -h "$b" | cut -f1)"
                mtime="$(date -r "$b" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -c '%y' "$b" 2>/dev/null || echo '?')"
                printf '  [%2d] %s  (%s, %s)\n' "$i" "$(basename "$b")" "$size" "$mtime" >&2
                ((i++))
            done
            local sel
            read -r -p "Pick a backup [1-${#backups[@]}, default=1]: " sel
            sel="${sel:-1}"
            if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#backups[@]} )); then
                err "Invalid selection: $sel"; return 1
            fi
            printf '%s' "${backups[$((sel-1))]}"; return 0
        fi
    fi

    printf '%s' "$newest"
}

BACKUP_FILE="$(resolve_target "$TARGET")" || exit 1
log "📂 Restore source: $BACKUP_FILE"

# 📊 pv detection (for live throughput / MB-per-second readout)
if command -v pv >/dev/null 2>&1; then
    make_pv() { pv -f -b -r -a -t -N "$1" -s "${2:-0}"; }
else
    warn "'pv' is not installed — install it for a live throughput readout (\`apt install pv\`)."
    make_pv() { cat; }
fi

# Choose a decompressor based on file extension.
case "$BACKUP_FILE" in
    *.sql.gz) DECOMPRESS=("gunzip" "-c") ;;
    *.sql)    DECOMPRESS=("cat") ;;
    *)        err "Unsupported file type (expecting .sql or .sql.gz): $BACKUP_FILE"; exit 1 ;;
esac

BACKUP_SIZE_BYTES="$(stat -c '%s' "$BACKUP_FILE" 2>/dev/null || stat -f '%z' "$BACKUP_FILE")"
log "📦 Size on disk: $(du -h "$BACKUP_FILE" | cut -f1)"
log "🎯 Restoring into: ${DEST_DB_USER}@${DEST_DB_HOST}/${DEST_DB_NAME}"

# 🛑 Confirmation
if [[ "$ASSUME_YES" -ne 1 ]]; then
    warn "This will OVERWRITE the local DB '${DEST_DB_NAME}' with the contents of:"
    warn "  $BACKUP_FILE"
    read -r -p "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { err "Aborted by user."; exit 1; }
fi

# -----------------------------------------------------------------------------
# 4️⃣  Take a safety snapshot of the *current* DB before we wipe it.
#     This way if you restored the wrong file, you can still recover.
# -----------------------------------------------------------------------------
if [[ "$DO_PRE_BACKUP" -eq 1 ]]; then
    mkdir -p "$BACKUP_DIR"
    PRE_TS="$(date +%Y%m%d-%H%M%S)"
    PRE_BACKUP="${BACKUP_DIR}/${DEST_DB_NAME}-pre-restore-${PRE_TS}.sql.gz"

    log "💾 Pre-restore safety backup → ${PRE_BACKUP}"
    mysqldump --defaults-extra-file="$DEST_DEFAULTS_FILE" \
        --single-transaction --quick --routines --triggers --events \
        --default-character-set=utf8mb4 \
        --no-tablespaces \
        "$DEST_DB_NAME" \
        | make_pv "💾 pre-restore (sql)" \
        | gzip -c > "$PRE_BACKUP"
    ok "✅ Pre-restore safety backup saved ($(du -h "$PRE_BACKUP" | cut -f1))"
else
    warn "Skipping pre-restore safety backup (--no-backup)."
fi

# -----------------------------------------------------------------------------
# 5️⃣  Stream the backup into mysql.
#     Pipeline:
#       (gunzip|cat) backup → pv (📊 live MB/s) → mysql
#     pv gets the on-disk byte count for .sql files (gives a real % bar);
#     for .sql.gz we pass 0 so pv just shows bytes/rate/elapsed without %.
# -----------------------------------------------------------------------------
log "⬆️  Restoring …"
if [[ "$BACKUP_FILE" == *.sql ]]; then
    PV_SIZE="$BACKUP_SIZE_BYTES"
else
    PV_SIZE=0   # uncompressed size unknown without reading the file twice
fi

"${DECOMPRESS[@]}" "$BACKUP_FILE" \
    | make_pv "⬆️  restore (sql)" "$PV_SIZE" \
    | mysql --defaults-extra-file="$DEST_DEFAULTS_FILE" "$DEST_DB_NAME"

ok "🎉 Restore complete: ${BACKUP_FILE} → ${DEST_DB_NAME}"
if [[ "$DO_PRE_BACKUP" -eq 1 ]]; then
    log "🔁 If you need to undo this restore, the pre-restore snapshot is at:"
    log "     ${PRE_BACKUP}"
fi

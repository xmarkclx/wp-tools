#!/usr/bin/env bash
# 🖼️  sync-uploads.sh — Pull the remote WordPress uploads/ directory down to
#                       the local project using rsync.
#
# 📥 Reads (all from ./src.env in the current working directory):
#   SSH_HOST=user@host.example.com           # required
#   WP_DIR=/var/www/.../httpdocs             # required (remote project root)
#   SSH_PORT=22                              # optional, default 22
#   SRC_UPLOADS_DIR=web/app/uploads          # optional, default web/app/uploads (Bedrock)
#   DEST_UPLOADS_DIR=web/app/uploads         # optional, default web/app/uploads (Bedrock)
#   UPLOADS_EXCLUDE='cache/* *.log'          # optional, space-separated rsync exclude patterns
#
# 🚀 Usage:
#   ./sync-uploads.sh                        # transfers immediately (no prompt)
#   ./sync-uploads.sh -n                     # dry-run — show what WOULD transfer
#
#   The script never prompts. It's designed to be streamed and run
#   non-interactively. It is also strictly non-destructive: rsync only
#   ADDS and UPDATES files locally — it will never delete anything.
#   If you genuinely need mirror-with-deletion semantics, run rsync
#   manually with --delete (deliberately not exposed here as a flag).

set -euo pipefail

# 🎨 Pretty logging helpers (same vocabulary as sync-db.sh)
log()  { printf '\033[1;34m[sync-uploads]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[sync-uploads]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[sync-uploads]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[sync-uploads]\033[0m %s\n' "$*" >&2; }

# 📁 Always operate on the current working directory — see sync-db.sh for rationale.
SCRIPT_DIR="${SYNC_DB_DIR:-$PWD}"
cd "$SCRIPT_DIR"

SRC_ENV_FILE="${SCRIPT_DIR}/src.env"

# 🤖 CLI flags — kept minimal; the script never prompts (streaming-first design).
DRY_RUN=0
while (( $# > 0 )); do
    case "$1" in
        -n|--dry-run)    DRY_RUN=1; shift ;;
        -h|--help)       sed -n '1,22p' "$0"; exit 0 ;;
        *)               err "Unknown argument: $1"; exit 1 ;;
    esac
done

# -----------------------------------------------------------------------------
# 🔍 get_env_value — same helper as sync-db.sh
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

# -----------------------------------------------------------------------------
# 1️⃣  Read src.env
# -----------------------------------------------------------------------------
[[ -f "$SRC_ENV_FILE" ]] || { err "Missing $SRC_ENV_FILE"; exit 1; }

SSH_HOST="$(get_env_value "$SRC_ENV_FILE" SSH_HOST)" || { err "SSH_HOST missing in src.env"; exit 1; }
WP_DIR="$(get_env_value "$SRC_ENV_FILE" WP_DIR)"     || { err "WP_DIR missing in src.env";   exit 1; }
SSH_PORT="$(get_env_value "$SRC_ENV_FILE" SSH_PORT 2>/dev/null || true)"
SSH_PORT="${SSH_PORT:-22}"

# 📂 Upload paths — default to Bedrock layout on both sides.
SRC_UPLOADS_DIR="$(get_env_value "$SRC_ENV_FILE" SRC_UPLOADS_DIR 2>/dev/null || true)"
SRC_UPLOADS_DIR="${SRC_UPLOADS_DIR:-web/app/uploads}"
DEST_UPLOADS_DIR="$(get_env_value "$SRC_ENV_FILE" DEST_UPLOADS_DIR 2>/dev/null || true)"
DEST_UPLOADS_DIR="${DEST_UPLOADS_DIR:-web/app/uploads}"

# Strip leading/trailing slashes for predictable joining; we add them back below.
SRC_UPLOADS_DIR="${SRC_UPLOADS_DIR#/}"; SRC_UPLOADS_DIR="${SRC_UPLOADS_DIR%/}"
DEST_UPLOADS_DIR="${DEST_UPLOADS_DIR#/}"; DEST_UPLOADS_DIR="${DEST_UPLOADS_DIR%/}"

# 🚫 Optional exclude patterns (space-separated)
UPLOADS_EXCLUDE="$(get_env_value "$SRC_ENV_FILE" UPLOADS_EXCLUDE 2>/dev/null || true)"

# -----------------------------------------------------------------------------
# 2️⃣  Build the source/destination URLs.
# -----------------------------------------------------------------------------
REMOTE_PATH="${WP_DIR%/}/${SRC_UPLOADS_DIR}/"     # ⚠️ trailing slash = "contents of"
LOCAL_PATH="${SCRIPT_DIR%/}/${DEST_UPLOADS_DIR}/" # ⚠️ trailing slash = "into this dir"

log "🌐 Source: ${SSH_HOST}:${REMOTE_PATH} (port ${SSH_PORT})"
log "📂 Dest  : ${LOCAL_PATH}"

# -----------------------------------------------------------------------------
# 3️⃣  Build the rsync command.
# -----------------------------------------------------------------------------
RSYNC_OPTS=(
    -avz
    --human-readable
    --info=progress2,stats2
    --partial
    --append-verify     # 📡 resumable — handy on flaky/slow links
    -e "ssh -p ${SSH_PORT}"
)

# Apply user-defined excludes (split UPLOADS_EXCLUDE on whitespace)
if [[ -n "$UPLOADS_EXCLUDE" ]]; then
    # shellcheck disable=SC2206
    EXCLUDES=( $UPLOADS_EXCLUDE )
    for pattern in "${EXCLUDES[@]}"; do
        RSYNC_OPTS+=( --exclude="$pattern" )
    done
fi

# Dry-run flag
if [[ "$DRY_RUN" -eq 1 ]]; then
    RSYNC_OPTS+=( --dry-run )
fi

# 🛡️ Note: --delete is intentionally NOT supported here. rsync's default
#         behaviour (add/update only, never remove) is the safe choice for
#         a streaming-first script that anyone can pipe into bash.

# -----------------------------------------------------------------------------
# 4️⃣  Announce intent (no prompt — streaming-first)
# -----------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
    log "🧪 Dry-run mode — nothing will actually be transferred."
fi

# -----------------------------------------------------------------------------
# 5️⃣  Run rsync
# -----------------------------------------------------------------------------
mkdir -p "$LOCAL_PATH"

log "🚚 Running rsync …"
rsync "${RSYNC_OPTS[@]}" "${SSH_HOST}:${REMOTE_PATH}" "${LOCAL_PATH}"

if [[ "$DRY_RUN" -eq 1 ]]; then
    ok "✅ Dry-run complete — see the file list above. Re-run without -n to actually transfer."
else
    ok "🎉 Uploads sync complete: ${SSH_HOST}:${REMOTE_PATH} → ${LOCAL_PATH}"
fi

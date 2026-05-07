#!/usr/bin/env bash
# 📦 install.sh — Install wp-tools commands into ~/bin and ensure PATH.
#
# 🚀 Usage:
#   curl -fsSL https://raw.githubusercontent.com/xmarkclx/wp-tools/main/install.sh | bash

set -euo pipefail

SCRIPT_NAME="install-wp-tools"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
ok()   { printf '\033[1;32m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
err()  { printf '\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2; }

DEFAULT_BASE_URL="https://raw.githubusercontent.com/xmarkclx/wp-tools/main"
BASE_URL="${WP_TOOLS_INSTALL_BASE_URL:-$DEFAULT_BASE_URL}"
INSTALL_DIR="${WP_TOOLS_INSTALL_DIR:-$HOME/bin}"
COMMANDS=(
    wp-sync-all
    wp-sync-db
    wp-sync-files
    wp-sync-uploads
    wp-restore-db
    wp-tools-lib.sh
)

usage() {
    sed -n '1,8p' "$0"
}

while (( $# > 0 )); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *)         err "❌ Unknown argument: $1"; exit 1 ;;
    esac
done

detect_profile() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)  printf '%s' "$HOME/.zshrc" ;;
        bash)
            if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
                printf '%s' "$HOME/.bash_profile"
            else
                printf '%s' "$HOME/.bashrc"
            fi
            ;;
        fish) printf '%s' "$HOME/.config/fish/config.fish" ;;
        *)    printf '%s' "$HOME/.profile" ;;
    esac
}

detect_path_line() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        fish) printf '%s' 'fish_add_path "$HOME/bin"' ;;
        *)    printf '%s' 'export PATH="$HOME/bin:$PATH"' ;;
    esac
}

install_from_local_repo() {
    local source_dir="$1" target="$2" source_path
    source_path="${source_dir}/${target}"
    [[ -f "$source_path" ]] || return 1
    cp "$source_path" "${INSTALL_DIR}/${target}"
}

install_from_url() {
    local target="$1" url
    url="${BASE_URL%/}/${target}"
    command -v curl >/dev/null 2>&1 || { err "❌ curl is required to install ${target}"; exit 1; }
    curl -fsSL "$url" -o "${INSTALL_DIR}/${target}" || { err "❌ Failed to download ${url}"; exit 1; }
}

log "📦 Installing wp-tools commands into ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

SOURCE_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

for command in "${COMMANDS[@]}"; do
    if [[ -n "$SOURCE_DIR" ]] && install_from_local_repo "$SOURCE_DIR" "$command"; then
        :
    else
        install_from_url "$command"
    fi

    if [[ "$command" == *.sh ]]; then
        chmod 0644 "${INSTALL_DIR}/${command}"
    else
        chmod 0755 "${INSTALL_DIR}/${command}"
    fi
    ok "✅ Installed ${command}"
done

PROFILE_FILE="$(detect_profile)"
PATH_LINE="$(detect_path_line)"
mkdir -p "$(dirname "$PROFILE_FILE")"
touch "$PROFILE_FILE"

if grep -Fqx "$PATH_LINE" "$PROFILE_FILE"; then
    ok "✅ PATH already includes ~/bin in ${PROFILE_FILE}"
else
    printf '\n%s\n' "$PATH_LINE" >> "$PROFILE_FILE"
    ok "✅ Added ~/bin to PATH in ${PROFILE_FILE}"
fi

export PATH="$HOME/bin:$PATH"

ok "🎉 Install complete"
warn "🔁 Open a new terminal or run: source ${PROFILE_FILE}"

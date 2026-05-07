#!/usr/bin/env bash

wp_tools_set_script_name() {
    WP_TOOLS_SCRIPT_NAME="$1"
}

wp_log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$WP_TOOLS_SCRIPT_NAME" "$*"; }
wp_ok()   { printf '\033[1;32m[%s]\033[0m %s\n' "$WP_TOOLS_SCRIPT_NAME" "$*"; }
wp_warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$WP_TOOLS_SCRIPT_NAME" "$*"; }
wp_err()  { printf '\033[1;31m[%s]\033[0m %s\n' "$WP_TOOLS_SCRIPT_NAME" "$*" >&2; }

wp_command_dir() {
    local source_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    cd "$(dirname "$source_path")" && pwd
}

wp_project_dir() {
    if [[ -n "${WP_TOOLS_DIR:-}" ]]; then
        printf '%s' "$WP_TOOLS_DIR"
    elif [[ -n "${SYNC_DB_DIR:-}" ]]; then
        printf '%s' "$SYNC_DB_DIR"
    else
        printf '%s' "$PWD"
    fi
}

wp_get_env_value() {
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

wp_require_file() {
    local file="$1"
    [[ -f "$file" ]] || { wp_err "❌ Missing $file"; exit 1; }
    wp_ok "📄 Found ${file}"
}

wp_require_env_key() {
    local file="$1" label="$2" key="$3"
    local value
    value="$(wp_get_env_value "$file" "$key")" || { wp_err "❌ ${key} missing in ${label}"; exit 1; }
    [[ -n "$value" ]] || { wp_err "❌ ${key} is empty in ${label}"; exit 1; }
    wp_ok "✅ ${label} has ${key}"
}

wp_escape_mycnf_value() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '"%s"' "$v"
}

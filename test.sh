#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="test.sh"
COLOR="blue"
ENV_FILE=".env"
PROMPT=0
SHOW_ENV=0
POSITIONAL=()

usage() {
    cat <<'EOF'
Usage:
  curl -fsSL https://example.test/test.sh | bash -s -- [options] [args...]

Options:
  --color <name>   Set output color: blue, green, yellow, red, magenta, cyan, none
  --no-color       Disable ANSI colors
  --env <path>     Read a specific env file (default: .env)
  --show-env       Print env file contents
  --prompt         Ask for input using /dev/tty
  -h, --help       Show this help
EOF
}

die() {
    printf '\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --color)
            [[ $# -ge 2 ]] || die "--color requires a value"
            COLOR="$2"
            shift 2
            ;;
        --color=*)
            COLOR="${1#*=}"
            shift
            ;;
        --no-color)
            COLOR="none"
            shift
            ;;
        --env)
            [[ $# -ge 2 ]] || die "--env requires a path"
            ENV_FILE="$2"
            shift 2
            ;;
        --env=*)
            ENV_FILE="${1#*=}"
            shift
            ;;
        --show-env)
            SHOW_ENV=1
            shift
            ;;
        --prompt)
            PROMPT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while (($# > 0)); do
                POSITIONAL+=("$1")
                shift
            done
            ;;
        -*)
            die "Unknown argument: $1"
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

color_code() {
    case "$1" in
        blue)    printf '1;34' ;;
        green)   printf '1;32' ;;
        yellow)  printf '1;33' ;;
        red)     printf '1;31' ;;
        magenta) printf '1;35' ;;
        cyan)    printf '1;36' ;;
        none)    return 1 ;;
        *)       die "Unsupported color: $1" ;;
    esac
}

say() {
    local code
    if code="$(color_code "$COLOR")"; then
        printf '\033[%sm[%s]\033[0m %s\n' "$code" "$SCRIPT_NAME" "$*"
    else
        printf '[%s] %s\n' "$SCRIPT_NAME" "$*"
    fi
}

say "Streaming worked!"

printf 'Arguments (%d):\n' "${#POSITIONAL[@]}"
if ((${#POSITIONAL[@]} > 0)); then
    for i in "${!POSITIONAL[@]}"; do
        printf '  %d: %s\n' "$((i + 1))" "${POSITIONAL[$i]}"
    done
else
    printf '  none\n'
fi

if ((SHOW_ENV)); then
    if [[ -f "$ENV_FILE" ]]; then
        printf '.env contents:\n'
        sed -n '1,200p' "$ENV_FILE"
    else
        say "No env file found at ${ENV_FILE}"
    fi
fi

if ((PROMPT)); then
    [[ -r /dev/tty ]] || die "Cannot prompt because /dev/tty is unavailable"
    answer=""
    read -r -p "Enter test input: " answer </dev/tty
    printf 'You entered: %s\n' "$answer"
fi

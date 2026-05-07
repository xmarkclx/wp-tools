# Streaming CLI

Yeah — `curl | bash` installers have a bunch of gotchas beyond prompts.

## 1. `stdin` is not safe to use

You already hit this. Anything that reads from stdin can break:

```bash
read answer
select option in ...
sudo -v
ssh ...
```

Use `/dev/tty` for interactive input:

```bash
read -r -p "Continue? " answer </dev/tty
```

For commands that may need user interaction:

```bash
sudo -v </dev/tty
```

## 2. Arguments need `bash -s --`

This:

```bash
curl -fsSL https://x.sh | bash --yes
```

does **not** reliably pass `--yes` to the script the way people expect.

Use:

```bash
curl -fsSL https://x.sh | bash -s -- --yes
```

Inside the script:

```bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --version) VERSION="$2"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done
```

## 3. `set -e` has weird edge cases

This is common:

```bash
set -e
```

But `set -e` does not behave consistently inside conditionals, pipes, subshells, command substitutions, etc.

Better default:

```bash
set -Eeuo pipefail
```

But even then, be careful with expected failures:

```bash
if grep -q "thing" file.txt; then
  echo "found"
else
  echo "not found"
fi
```

Avoid this under `set -e` unless handled:

```bash
grep -q "thing" file.txt
echo "continuing"
```

If `grep` finds nothing, the script exits.

## 4. `pipefail` matters

Without `pipefail`, this can look successful even if `curl` failed:

```bash
curl -fsSL "$url" | tar -xz
```

Use:

```bash
set -o pipefail
```

Or safer:

```bash
tmp="$(mktemp -d)"
curl -fsSL "$url" -o "$tmp/archive.tar.gz"
tar -xzf "$tmp/archive.tar.gz" -C "$tmp"
```

I prefer downloading to a temp file because it is easier to verify checksums and debug.

## 5. Temporary files need cleanup

Use `mktemp`, not predictable paths like `/tmp/mytool`.

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
```

Avoid:

```bash
tmp="/tmp/install"
mkdir -p "$tmp"
```

That can collide or create security issues.

## 6. Detect OS and architecture carefully

`uname -m` returns different names depending on platform:

```bash
arch="$(uname -m)"

case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  arm64|aarch64) arch="arm64" ;;
  *) die "Unsupported architecture: $arch" ;;
esac
```

OS too:

```bash
os="$(uname -s | tr '[:upper:]' '[:lower:]')"

case "$os" in
  linux) os="linux" ;;
  darwin) os="darwin" ;;
  *) die "Unsupported OS: $os" ;;
esac
```

## 7. macOS uses older Bash

macOS often ships an old Bash version. Avoid Bash 4+ features if you want broad compatibility:

Avoid associative arrays:

```bash
declare -A map
```

Avoid modern Bash-only niceties unless you explicitly require a newer Bash.

For broad installers, keep it boring.

## 8. Some systems have no `bash`

Minimal containers or Alpine systems may not have Bash by default.

For maximum compatibility, write POSIX `sh`:

```bash
curl -fsSL https://x.sh | sh
```

But if you need Bash, fail clearly:

```bash
#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  echo "This installer requires bash." >&2
  exit 1
fi
```

## 9. `sudo` is annoying

Do not blindly use `sudo`.

Check whether you need it:

```bash
if [ "$EUID" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi
```

Then:

```bash
$SUDO install -m 0755 mytool /usr/local/bin/mytool
```

But also consider defaulting to user-local install:

```bash
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
```

That avoids sudo entirely.

## 10. `$HOME/.local/bin` may not be in `PATH`

After installing to:

```bash
$HOME/.local/bin
```

Check:

```bash
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    echo "Add this to your shell profile:"
    echo 'export PATH="$HOME/.local/bin:$PATH"'
    ;;
esac
```

## 11. Shell profile detection is messy

Avoid editing `.bashrc`, `.zshrc`, `.profile`, etc. unless you really need to.

If you do, make it explicit and idempotent:

```bash
line='export PATH="$HOME/.local/bin:$PATH"'

if ! grep -Fq "$line" "$HOME/.profile" 2>/dev/null; then
  printf '\n%s\n' "$line" >> "$HOME/.profile"
fi
```

Do not append blindly every run.

## 12. Make the script idempotent

Running the installer twice should not break things.

Good:

```bash
mkdir -p "$INSTALL_DIR"
install -m 0755 "$tmp/mytool" "$INSTALL_DIR/mytool"
```

Bad:

```bash
echo 'export PATH=...' >> ~/.bashrc
```

without checking if it already exists.

## 13. Verify downloads

For public tools, do checksum verification:

```bash
curl -fsSL "$url" -o "$tmp/file.tar.gz"
curl -fsSL "$url.sha256" -o "$tmp/file.tar.gz.sha256"

cd "$tmp"
sha256sum -c file.tar.gz.sha256
```

On macOS, `sha256sum` may not exist. You may need:

```bash
shasum -a 256 file.tar.gz
```

So you either handle both or publish platform-specific verification instructions.

## 14. Do not pipe huge logic directly into shell if you can avoid it

A better pattern is:

```bash
curl -fsSL https://x.sh -o install.sh
bash install.sh
```

For users, provide both:

```bash
curl -fsSL https://x.sh | bash
```

and:

```bash
curl -fsSL https://x.sh -o install.sh
less install.sh
bash install.sh
```

## 15. Avoid relying on aliases/functions

Non-interactive shells do not load the user’s usual aliases.

This may work in your terminal:

```bash
ll
```

But fail in scripts.

Use real commands:

```bash
ls -la
```

Also avoid assuming things like `nvm`, `rbenv`, `pyenv`, or `brew` are loaded unless you load/detect them.

## 16. Quote everything

Bad:

```bash
rm -rf $INSTALL_DIR/$APP_NAME
```

Good:

```bash
rm -rf "$INSTALL_DIR/$APP_NAME"
```

Paths with spaces, empty variables, and glob expansion can wreck scripts.

## 17. Be careful with destructive commands

Protect against empty vars:

```bash
: "${INSTALL_DIR:?INSTALL_DIR is required}"
: "${APP_NAME:?APP_NAME is required}"

rm -rf "$INSTALL_DIR/$APP_NAME"
```

Never do things like:

```bash
rm -rf "$INSTALL_DIR"/*
```

unless you are very sure.

## 18. Prefer explicit dependencies

Check dependencies upfront:

```bash
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

need curl
need tar
```

For optional tools, branch:

```bash
if command -v sudo >/dev/null 2>&1; then
  SUDO=sudo
else
  SUDO=""
fi
```

## 19. Do not assume GNU tools

macOS BSD utilities differ from Linux GNU utilities.

Gotchas:

```bash
sed -i
readlink -f
date -d
base64 -w 0
realpath
```

These may behave differently or not exist on macOS.

For installers, avoid clever `sed`/`awk`/`date` usage unless tested on both Linux and macOS.

## 20. Make non-interactive mode first-class

Support:

```bash
curl -fsSL https://x.sh | bash -s -- --yes
```

Also support env vars:

```bash
curl -fsSL https://x.sh | INSTALL_DIR="$HOME/bin" bash
```

Common flags:

```bash
--yes
--version 1.2.3
--install-dir /path
--dry-run
--uninstall
```

## 21. Use good curl flags

Common:

```bash
curl -fsSL "$url"
```

Meaning:

```text
-f  fail on HTTP errors
-s  silent
-S  show errors even when silent
-L  follow redirects
```

For scripts, I usually use:

```bash
curl --proto '=https' --tlsv1.2 -fsSL "$url"
```

That prevents accidentally using non-HTTPS protocols.

## 22. Print commands only in debug mode

Support:

```bash
DEBUG=1 curl -fsSL https://x.sh | bash
```

Inside:

```bash
if [ "${DEBUG:-0}" = "1" ]; then
  set -x
fi
```

Do not enable `set -x` by default because it can leak secrets.

## 23. Secrets can leak easily

Avoid echoing tokens.

Bad:

```bash
echo "Using token $API_TOKEN"
```

Bad with debug:

```bash
set -x
curl -H "Authorization: Bearer $API_TOKEN" ...
```

If handling secrets, disable tracing around them:

```bash
set +x
# secret command here
[ "${DEBUG:-0}" = "1" ] && set -x
```

## 24. Signals and partial installs

If the user hits Ctrl+C halfway, you can leave broken files.

Use temp locations, then move atomically:

```bash
install -m 0755 "$tmp/mytool" "$INSTALL_DIR/mytool"
```

For multi-file installs, install into a versioned directory first, then update a symlink at the end.

## 25. Have a clear failure function

```bash
die() {
  echo "Error: $*" >&2
  exit 1
}
```

Use it everywhere:

```bash
[ -w "$INSTALL_DIR" ] || die "Install dir is not writable: $INSTALL_DIR"
```

## My preferred pattern

For a serious installer:

```bash
curl -fsSL https://example.com/install.sh | bash -s -- --yes
```

The streamed Bash script should only:

1. parse args/env vars
2. detect OS/arch
3. check dependencies
4. download a versioned release artifact
5. verify checksum
6. install into a safe directory
7. print next steps

Avoid making the streamed script the whole application. Use it as a small bootstrapper.

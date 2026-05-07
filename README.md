# wp-tools

These are tools to help me easily manage tons of Wordpress sites.

Install the commands once:

```bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/install.sh' | bash
```

The installer puts commands in `~/bin` and adds this line to your shell profile if needed:

```bash
export PATH="$HOME/bin:$PATH"
```

After install, open a new terminal or source the profile file printed by the installer.

Then run tools from any WordPress project folder:

```bash
wp-sync-db
wp-restore-db latest
wp-sync-files --dry-run
wp-sync-all
```

# Versioning

If you want to pin to a specific version:

```bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/v1.0.0/install.sh' \
  | WP_TOOLS_INSTALL_BASE_URL='https://raw.githubusercontent.com/xmarkclx/wp-tools/v1.0.0' bash
```

# Conventions

## sync.env

```dotenv
# Required: SSH target for the remote/source site.
SSH_HOST=user@host.example.com

# Required: remote/source WordPress root.
WP_DIR=/var/www/vhosts/example.com/httpdocs

# Optional: SSH port. Defaults to 22.
SSH_PORT=22

# Optional: file sync source path relative to WP_DIR.
# Use "." to sync the whole WP_DIR.
SRC_SYNC_DIR=.

# Optional: file sync destination path relative to the current local project.
# Use "." to sync into the current project folder.
DEST_SYNC_DIR=.

# Optional: extra rsync exclude patterns, split on spaces.
# wp-sync-files always excludes .env, sync.env, and backups/ by default.
SYNC_EXCLUDE='node_modules/* vendor/* web/app/cache/*'

# Optional: legacy uploads-only sync paths.
SRC_UPLOADS_DIR=web/app/uploads
DEST_UPLOADS_DIR=web/app/uploads
UPLOADS_EXCLUDE='cache/* *.log'
```

# Tools

## wp-sync-db

Reads from your `.env` and `sync.env`, then syncs data from source to current.

## wp-restore-db

Restores db.

## wp-sync-files

Syncs files from the configured remote folder to the configured local folder.

By default it syncs the whole `WP_DIR` to the current project folder, while excluding `.env`, `sync.env`, and `backups/`.

## wp-sync-uploads

Legacy uploads-only sync.

## wp-sync-all

Checks `sync.env` and `.env`, then runs the database sync followed by the files sync.

Use `--files-dry-run` to run the DB sync normally and dry-run only the files sync:

```bash
wp-sync-all --files-dry-run
```

# Backups

This will create a `backups` folder which will contain a `db` folder.

# License

MIT LICENSE

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

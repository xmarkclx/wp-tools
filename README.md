# wp-tools

These are tools to help me easily manage tons of Wordpress sites.

You don't need to clone this, you can run these via streaming as per the instructions.

i.e.

```bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-db.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/restore-db.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-uploads.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-all.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/test.sh' | bash -s -- --show-env --color red
```

# Versioning

If you want to pin to a specific version:

```bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/v1.0.0/test.sh' | bash
```

# Conventions

## src.env

```
SSH_HOST=user@host.example.com
WP_DIR=/var/www/vhosts/example.com/httpdocs
```

# Tools

## sync-db.sh

Reads from your .env and the src.env and then syncs data from src to current.

## restore-db.sh

Restores db.

## sync-uploads.sh

Syncs upload folder.

## sync-all.sh

Checks `src.env` and `.env`, then runs the database sync followed by the uploads sync.

Use `--uploads-dry-run` to run the DB sync normally and dry-run only the uploads sync:

```bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-all.sh' | bash -s -- --uploads-dry-run
```

# Backups

This will create a `backups` folder which will contain a `db` folder.

# License

MIT

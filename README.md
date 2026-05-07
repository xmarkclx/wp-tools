# wp-tools

These are tools to help me easily manage tons of Wordpress sites.

You don't need to clone this, you can run these via streaming as per the instructions.

i.e.

```bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/test.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-db.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/restore-db.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-uploads.sh' | bash
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

# Backups

This will create a `backups` folder which will contain a `db` folder.

# License

MIT

# wp-tools

These are tools to help me easily manage tons of Wordpress sites.

You don't need to clone this, you can run these via streaming as per the instructions.

i.e.

```bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/test.sh' | bash
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/sync-db.sh' | bash -s --y
curl -fsSL 'https://raw.githubusercontent.com/xmarkclx/wp-tools/main/restore-db.sh' | bash -s --y
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

Usage:

```ash
./sync-db.sh           # interactive — confirms before overwriting
./sync-db.sh -y        # no confirmation (CI / cron)
```

## restore-db.sh

Restores db.

```bash
./restore-db.sh                           # interactive picker (lists backups)
./restore-db.sh latest                    # newest in backups/db/
./restore-db.sh backups/db/foo.sql.gz     # specific file
./restore-db.sh -y latest                 # no confirmation
./restore-db.sh --no-backup latest        # skip the pre-restore safety snapshot
```

# Backups

This will create a `backups` folder which will contain a `db` folder.

# License

MIT

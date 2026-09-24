# Backups, upgrades, and rollback

Read this before any change that writes to the server, and whenever the user
is upgrading, downgrading, or recovering from a failed upgrade.

## What a complete backup contains

A Silo backup needs all of these. Missing any one can make the rest useless.

| Piece | Why | Docker Compose default | Unraid default |
|---|---|---|---|
| PostgreSQL dump | Catalog, users, settings, watch history | `postgres` service | `Silo-PostgreSQL` container |
| `SECRET_KEY` | Decrypts every stored credential. A dump restored with a different key has unreadable secrets. | `.env` | Silo container's `SECRET_KEY` variable |
| Compose files and `.env` (or the container template) | Recreates the same deployment | repo checkout | `/boot/config/plugins/dockerMan/templates-user/` |
| Local artwork | Uploaded and cached artwork | `/opt/silo/artwork` | `/mnt/user/appdata/silo/artwork` |
| SQLite user data, only if `userdb.backend=sqlite` | Per-user state for that backend | `/var/lib/silo/userdb` (not persisted by default) | inside `/mnt/user/appdata/silo` |

Redis, the transcode directory, and the plugin cache are rebuilt automatically
and do not need backing up. Media files are the user's own responsibility.

## Take the backup

Docker Compose, from the directory that holds `docker-compose.yml`:

```sh
docker compose images silo                      # record the running image
docker compose exec -T postgres \
  pg_dump -U "${POSTGRES_USER:-silo}" -Fc "${POSTGRES_DB:-silo}" > silo-$(date +%F).dump
pg_restore --list silo-$(date +%F).dump > /dev/null && echo "dump is readable"
cp .env "silo-env-$(date +%F).backup" && chmod 600 "silo-env-$(date +%F).backup"
```

If `pg_restore` is not installed on the host, check the dump inside the
container instead:

```sh
docker compose exec -T postgres pg_restore --list < silo-$(date +%F).dump > /dev/null && echo "dump is readable"
```

Unraid (container names from the official templates):

```sh
docker exec Silo-PostgreSQL pg_dump -U silo -Fc silo > /mnt/user/backups/silo-$(date +%F).dump
docker exec -i Silo-PostgreSQL pg_restore --list < /mnt/user/backups/silo-$(date +%F).dump > /dev/null && echo "dump is readable"
```

Rules:

- Never copy the PostgreSQL data directory while PostgreSQL is running. That
  copy is inconsistent and may not start. Use `pg_dump`, or stop PostgreSQL
  first.
- Store the `SECRET_KEY` somewhere other than next to the dump, with
  restricted permissions.
- `docker compose config` prints the database password and `SECRET_KEY`.
  Never paste its output anywhere.

The agent must not print, read aloud, or copy the `SECRET_KEY` value into the
conversation. Confirm it exists (`grep -c '^SECRET_KEY=' .env`) and let the
user copy it.

## Upgrade

1. Take and verify the backup above.
2. Read the release or build notes for the target version. Some releases
   rewrite large tables and need extra time and free disk.
3. Pick the target with `SILO_IMAGE` in `.env` (a `build-N` tag, commit tag,
   or digest pins it; `latest` moves).
4. Update only the Silo service and watch it start:

   ```sh
   docker compose pull silo
   docker compose up -d --no-deps silo
   docker compose logs -f silo
   ```

5. Wait. Silo applies migrations at startup, under a database lock, before it
   opens its HTTP port. `docker ps` can show `unhealthy` after about a minute
   while a long migration is still running. **Do not restart the container
   during a migration.** That abandons the run and can leave a lock behind.
6. Migrations time out after 20 minutes by default. For a large library, set
   `SILO_MIGRATE_TIMEOUT=60m` (or `0` for no limit) before starting.
7. Confirm health:

   ```sh
   curl -fsS http://localhost:8090/api/v1/health
   curl -fsS http://localhost:8090/api/v1/ready
   ```

## Migration commands

These run against the configured database and exit:

```sh
docker compose run --rm silo --migrate-status        # read-only: list applied migrations
docker compose run --rm silo --migrate-only          # apply pending migrations, then exit
docker compose run --rm silo --migrate-down-to <ver> # DESTRUCTIVE: roll back to a version
```

`--migrate-status` is safe. The other two change the schema. Only run them
with a verified backup and the user's explicit approval.

## Rollback

- Silo does not promise that an older image can run on a newer schema.
  Rolling back the image alone does not undo migrations.
- Preferred rollback: stop the stack, restore the pre-upgrade dump, start the
  previously recorded image. This discards every change made after the dump.
- `--migrate-down-to` exists for reversible migrations, but some down
  migrations discard data, and it needs the newer image to run. Read the
  migration first and treat it as a last resort.
- Never downgrade to a very old build that predates encrypted settings. It
  would misread encrypted values.

## Restore a dump

This replaces the whole database. Only do it with the user's explicit
approval, after confirming which dump file and which `SECRET_KEY` belong
together.

```sh
docker compose stop silo
docker compose exec -T postgres dropdb -U "${POSTGRES_USER:-silo}" "${POSTGRES_DB:-silo}"
docker compose exec -T postgres createdb -U "${POSTGRES_USER:-silo}" "${POSTGRES_DB:-silo}"
docker compose exec -T postgres pg_restore -U "${POSTGRES_USER:-silo}" -d "${POSTGRES_DB:-silo}" --no-owner < silo-YYYY-MM-DD.dump
docker compose up -d silo
```

## Never do these

- Run `goose fix`, or rename or renumber files in the migrations directory.
- Rename a row in `server_settings`. Encrypted values are bound to their key
  name and become permanently unreadable.
- Change or regenerate `SECRET_KEY` on an existing install. Every stored
  credential becomes unreadable, and all sessions are invalidated.
- Hand-edit the schema, drop tables, or delete rows to "clean up".
- Delete `SILO_DATA_ROOT` or the PostgreSQL data directory to "start fresh"
  without a verified backup and an explicit request from the user.
- Change the S3 bucket, endpoint, or path of an existing artwork store in
  settings. Silo refuses to start against a different storage identity; moving
  storage goes through the storage transition in **Admin > Settings >
  Infrastructure**.

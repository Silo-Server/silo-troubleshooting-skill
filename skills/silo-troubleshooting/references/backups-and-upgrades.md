# Backups, upgrades, and rollback

Read this before any change that writes to the server, and whenever the user
is upgrading, downgrading, or recovering from a failed upgrade.

## What a complete backup contains

A Silo backup needs all of these. Missing any one can make the rest useless.

| Piece | Why | Docker Compose default | Unraid default |
|---|---|---|---|
| PostgreSQL dump | Catalog, users, settings, watch history | `postgres` service | `Silo-PostgreSQL` container |
| `SECRET_KEY` | Decrypts every stored credential. With a different key, Silo refuses to start on the restored database. | `.env` | Silo container's `SECRET_KEY` variable |
| The exact build that is running | Needed to roll back; `latest` does not identify it | see below | see below |
| Compose files and `.env` (or the container template) | Recreates the same deployment | repo checkout | `/boot/config/plugins/dockerMan/templates-user/` |
| Local artwork | Uploaded and cached artwork | `/opt/silo/artwork` | `/mnt/user/appdata/silo/artwork` |
| SQLite user data, only if `userdb.backend=sqlite` | Per-user state for that backend | `/var/lib/silo/userdb` (not persisted by default) | inside `/mnt/user/appdata/silo` |

Redis, the transcode directory, and the plugin cache are rebuilt automatically
and do not need backing up. Media files are the user's own responsibility.

## Take the backup

Taking a dump only reads the database, so the agent may run these after
explaining them.

Docker Compose, from the directory that holds `docker-compose.yml`:

```sh
# 1. Record the running build (for rollback)
docker image inspect --format '{{join .RepoDigests " "}}' \
  "$(docker inspect --format '{{.Image}}' "$(docker compose ps -q silo)")"

# 2. Dump the database (uses the database's own user and name settings)
docker compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' > silo-$(date +%F).dump

# 3. Check the dump is readable
docker compose exec -T postgres pg_restore --list < silo-$(date +%F).dump > /dev/null && echo "dump is readable"
```

Also note the build number shown in the admin sidebar (or
`GET /api/v2/admin/system/build`). Published images carry `build-N` tags, so
that number maps to `ghcr.io/silo-server/silo-server:build-N`.

The user copies `.env` themselves, or the agent runs this without printing it:

```sh
cp .env "silo-env-$(date +%F).backup" && chmod 600 "silo-env-$(date +%F).backup"
```

Unraid (container names from the official templates):

```sh
mkdir -p /mnt/user/backups
docker exec Silo-PostgreSQL sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' > /mnt/user/backups/silo-$(date +%F).dump
docker exec -i Silo-PostgreSQL pg_restore --list < /mnt/user/backups/silo-$(date +%F).dump > /dev/null && echo "dump is readable"
```

Rules:

- Never copy the PostgreSQL data directory while PostgreSQL is running. That
  copy is inconsistent and may not start. Use `pg_dump`, or stop PostgreSQL
  first.
- Store the `SECRET_KEY` somewhere other than next to the dump, with
  restricted permissions. The user does this; the agent never prints the key.
  Confirm it exists with `grep -c '^SECRET_KEY=' .env`.
- `docker compose config` prints the database password and `SECRET_KEY`.
  Never run it in the agent's shell.

## Upgrade (Docker Compose)

1. Take and check the backup above, including the running build.
2. Read the release or build notes for the target version. Some releases
   rewrite large tables and need extra time and free disk.
3. Pick the target with `SILO_IMAGE` in `.env` (a `build-N` tag, commit tag,
   or digest pins it; `latest` moves).
4. For a large library, set `SILO_MIGRATE_TIMEOUT=60m` (or `0` for no limit)
   first. Migrations stop after 20 minutes by default.
5. Update only the Silo service:

   ```sh
   docker compose pull silo
   docker compose up -d --no-deps silo
   ```

6. Watch it start. The user can follow the logs in their own terminal with
   `docker compose logs -f silo`; the agent uses
   `docker compose logs --since 5m silo` and repeats.
7. Wait. Silo applies migrations at startup, under a database lock, before it
   opens its HTTP port. `docker ps` can show `unhealthy` after about a minute
   while a long migration is still running. **Do not restart the container
   during a migration.** That abandons the run and can leave a lock behind.
8. Confirm health:

   ```sh
   curl -fsS http://localhost:8090/api/v1/health
   curl -fsS http://localhost:8090/api/v1/ready
   ```

Unraid: take the backup, then use **Check for Updates** / **Apply Update** on
the Silo container (or set a pinned tag in the template's Repository field).
Watch the container log in the Unraid UI; the same "do not restart during a
migration" rule applies.

## Migration commands

The user runs these in their own terminal. The agent explains them and does
not run them, even with approval.

```sh
docker compose run --rm --no-deps silo --migrate-only          # apply pending migrations, then exit
docker compose run --rm --no-deps silo --migrate-down-to <ver> # roll the schema back; can discard data
```

Listing applied migrations (`--migrate-status`) is covered in
`startup-and-database.md`.

## Rollback

- Silo does not promise that an older image can run on a newer schema.
  Rolling back the image alone does not undo migrations.
- Preferred rollback: restore the pre-upgrade dump, then start the build
  recorded before the upgrade. This discards every change made after the
  dump.
- `--migrate-down-to` exists for reversible migrations, but some down
  migrations discard data, and it needs the newer image to run. Read the
  migration first and treat it as a last resort.
- Never downgrade to a very old build that predates encrypted settings. It
  would misread encrypted values.

## Restore a dump

This replaces the whole database. **The user runs these commands in their own
terminal.** The agent explains each step, and first confirms which dump file,
which `SECRET_KEY`, and which recorded build belong together.

```sh
# 1. Pin the build to return to, so startup does not re-apply newer migrations
#    Edit .env:  SILO_IMAGE=ghcr.io/silo-server/silo-server:build-N   (or @sha256:...)

# 2. Stop Silo and replace the database
docker compose stop silo
docker compose exec -T postgres sh -c 'dropdb -U "$POSTGRES_USER" "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
docker compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error' < silo-YYYY-MM-DD.dump

# 3. Start the pinned build
docker compose up -d silo
```

Unraid: stop the Silo container, then run the same `dropdb`/`createdb`/
`pg_restore` steps with `docker exec -i Silo-PostgreSQL ...`, set the pinned
tag in the Silo template, and start it.

## Never do these

- Run `goose fix`, or rename or renumber files in the migrations directory.
- Rename a row in `server_settings`. Encrypted values are bound to their key
  name and become permanently unreadable.
- Change or regenerate `SECRET_KEY` on an existing install. Silo will refuse
  to start, and stored credentials cannot be recovered without the old key.
- Hand-edit the schema, drop tables, or delete rows to "clean up".
- Delete `SILO_DATA_ROOT` or the PostgreSQL data directory to "start fresh"
  without a verified backup and an explicit request from the user.
- Change the S3 bucket, endpoint, or path of an existing artwork store in
  settings. Silo refuses to start against a different storage identity; moving
  storage goes through **Admin > Settings > Storage & Database**.

# Upgrades and rollback

Read this when the user is upgrading, downgrading, or recovering from a failed
upgrade.

## Backups are the user's job

Silo runs on too many kinds of setups (Compose, Unraid, Kubernetes, managed
databases, NAS snapshots, VM snapshots) for this skill to prescribe a backup
method. Do not write backup or restore commands for the user. Tell them to
back up with the tools they already use, and to check that the backup can be
restored.

A usable Silo backup covers:

- The PostgreSQL database.
- The `SECRET_KEY`, kept separately from the database backup. Without the same
  key, Silo refuses to start on a restored database.
- The deployment configuration (Compose files and `.env`, container templates,
  or manifests).
- Local artwork, if artwork is stored on disk rather than S3.

Redis, the transcode directory, and the plugin cache rebuild themselves and do
not need backing up.

## Before an upgrade

1. Confirm the user has a backup from today that they have checked.
2. Note the build that is running now; it is needed to roll back. The admin
   sidebar shows it, and with Compose the image digest is:

   ```sh
   docker image inspect --format '{{join .RepoDigests " "}}' \
     "$(docker inspect --format '{{.Image}}' "$(docker compose ps -q silo)")"
   ```

   Published images carry `build-N` tags, so the build number maps to
   `ghcr.io/silo-server/silo-server:build-N`. `latest` does not identify a
   build.
3. Read the release or build notes for the target version. Some releases
   rewrite large tables and need extra time and free disk.
4. For a large library, set `SILO_MIGRATE_TIMEOUT=60m` (or `0` for no limit).
   Migrations stop after 20 minutes by default.

## Upgrade (Docker Compose)

1. Pick the target with `SILO_IMAGE` in `.env` (a `build-N` tag, commit tag,
   or digest pins it; `latest` moves).
2. Update only the Silo service:

   ```sh
   docker compose pull silo
   docker compose up -d --no-deps silo
   ```

3. Watch it start. The user can follow the logs in their own terminal with
   `docker compose logs -f silo`; the agent uses
   `docker compose logs --since 5m silo` and repeats.
4. Wait. Silo applies migrations at startup, under a database lock, before it
   opens its HTTP port. `docker ps` can show `unhealthy` after about a minute
   while a long migration is still running. **Do not restart the container
   during a migration.** That abandons the run and can leave a lock behind.
5. Confirm health:

   ```sh
   curl -fsS http://localhost:8090/api/v1/health
   curl -fsS http://localhost:8090/api/v1/ready
   ```

Unraid: use **Check for Updates** / **Apply Update** on the Silo container (or
set a pinned tag in the template's Repository field), and watch the container
log in the Unraid UI. The same "do not restart during a migration" rule
applies.

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
- The rollback path is: the user restores their pre-upgrade backup with their
  own tools, pins `SILO_IMAGE` (or the Unraid template's tag) to the build
  noted before the upgrade, then starts Silo. Pin the build **before** starting,
  or Silo applies the newer migrations again. The restore discards every
  change made after the backup.
- The restored database and the `SECRET_KEY` must belong together.
- `--migrate-down-to` exists for reversible migrations, but some down
  migrations discard data, and it needs the newer image to run. Read the
  migration first and treat it as a last resort.
- Never downgrade to a very old build that predates encrypted settings. It
  would misread encrypted values.

## Never do these

- Run `goose fix`, or rename or renumber files in the migrations directory.
- Rename a row in `server_settings`. Encrypted values are bound to their key
  name and become permanently unreadable.
- Change or regenerate `SECRET_KEY` on an existing install. Silo will refuse
  to start, and stored credentials cannot be recovered without the old key.
- Hand-edit the schema, drop tables, or delete rows to "clean up".
- Delete `SILO_DATA_ROOT` or the PostgreSQL data directory to "start fresh"
  unless the user has a backup and explicitly asks for it.
- Change the S3 bucket, endpoint, or path of an existing artwork store in
  settings. Silo refuses to start against a different storage identity; moving
  storage goes through **Admin > Settings > Storage & Database**.
